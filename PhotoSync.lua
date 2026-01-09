local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrProgressScope = import 'LrProgressScope'
local LrPathUtils = import 'LrPathUtils'
local LrLogger = import 'LrLogger'
local LrFunctionContext = import 'LrFunctionContext'

-- 初始化日志记录器
local myLogger = LrLogger('RawSyncLogger')
-- 开发时开启，发布时可改为 "logfile"
myLogger:enable("print") 

local RawSync = {}

--------------------------------------------------------------------------------
-- 辅助函数：判断照片是否为 RAW 格式
--------------------------------------------------------------------------------
local function isRawFormat(photo)
    local format = photo:getRawMetadata('fileFormat')
    -- 'RAW' 代表通用 RAW，'DNG' 是数字负片。
    return format == 'RAW' or format == 'DNG'
end

--------------------------------------------------------------------------------
-- 核心算法：构建同文件夹下的 RAW 文件索引
--------------------------------------------------------------------------------
local function buildRawIndexForFolder(catalog, folderPath)
    local rawIndex = {}
    local folder = catalog:findFolderByPath(folderPath)
    if not folder then return rawIndex end
    local allPhotosInFolder = folder:getPhotos(false)
    for _, photo in ipairs(allPhotosInFolder) do
        if isRawFormat(photo) then
            local path = photo:getRawMetadata('path')
            local fileName = LrPathUtils.leafName(path)
            local baseName = LrPathUtils.removeExtension(fileName)
            rawIndex[baseName:lower()] = photo
        end
    end
    return rawIndex
end

--------------------------------------------------------------------------------
-- 通用同步逻辑
--------------------------------------------------------------------------------
local function executeSync(syncMode)
    LrFunctionContext.callWithContext('RawSync.executeSync', function(context)
        
        local catalog = LrApplication.activeCatalog()
        local selectedPhotos = catalog:getTargetPhotos()
        
        -- 筛选选中的 JPG
        local jpgPhotos = {}
        for _, photo in ipairs(selectedPhotos) do
            local fmt = photo:getRawMetadata('fileFormat')
            if fmt == 'JPG' then
                table.insert(jpgPhotos, photo)
            end
        end

        if #jpgPhotos == 0 then
            LrDialogs.message(LOC "$$$/RawSync/NoJpg=未选中 JPG 文件", nil, "info")
            return
        end

        -- 初始化进度条
        local progress = LrProgressScope({
            title = LOC "$$$/RawSync/Title=正在同步元数据...",
            functionContext = context
        })
        progress:setCancelable(true)

        LrTasks.startAsyncTask(function()
            local syncedCount = 0
            local skippedCount = 0
            local missingRawList = {}
            local photosByFolder = {}

            for _, photo in ipairs(jpgPhotos) do
                local path = photo:getRawMetadata('path')
                local parent = LrPathUtils.parent(path)
                if not photosByFolder[parent] then
                    photosByFolder[parent] = {}
                end
                table.insert(photosByFolder[parent], photo)
            end

            -- 逐个文件夹处理
            local totalFolders = 0
            for _ in pairs(photosByFolder) do totalFolders = totalFolders + 1 end
            local currentFolderIdx = 0

            -- 收集所有需要执行的写入操作，稍后分批执行
            local tasks = {} 

            for folderPath, photos in pairs(photosByFolder) do
                currentFolderIdx = currentFolderIdx + 1
                if progress:isCanceled() then return end
                
                progress:setCaption(string.format("正在分析文件夹 (%d/%d): %s", currentFolderIdx, totalFolders, LrPathUtils.leafName(folderPath)))

                -- 构建该文件夹的 RAW 索引
                local rawIndex = buildRawIndexForFolder(catalog, folderPath)

                for _, jpgPhoto in ipairs(photos) do
                    local jpgPath = jpgPhoto:getRawMetadata('path')
                    local baseName = LrPathUtils.removeExtension(LrPathUtils.leafName(jpgPath))
                    local rawPhoto = rawIndex[baseName:lower()]

                    if rawPhoto then
                        -- 读取 JPG 元数据
                        local dataToSync = {
                            raw = rawPhoto,
                            jpg = jpgPhoto -- 用于调试或日志
                        }
                        
                        -- 根据模式读取不同数据
                        if syncMode == "flags" or syncMode == "all" then
                            dataToSync.pickStatus = jpgPhoto:getRawMetadata('pickStatus')
                        end
                        if syncMode == "ratings" or syncMode == "all" then
                            dataToSync.rating = jpgPhoto:getRawMetadata('rating')
                        end
                        if syncMode == "colors" or syncMode == "all" then
                            dataToSync.colorLabel = jpgPhoto:getRawMetadata('colorNameForLabel')
                        end

                        table.insert(tasks, dataToSync)
                    else
                        table.insert(missingRawList, LrPathUtils.leafName(jpgPath))
                    end
                end
            end

            -- 分批写入 (Batch Processing)
            -- Lightroom 建议不要在一个事务中处理过多照片，否则 UI 会卡死
            local BATCH_SIZE = 300
            local totalTasks = #tasks
            
            for i = 1, totalTasks, BATCH_SIZE do
                if progress:isCanceled() then break end
                
                local endIndex = math.min(i + BATCH_SIZE - 1, totalTasks)
                progress:setPortionComplete(i, totalTasks)
                progress:setCaption(string.format("正在同步数据... %d/%d", i, totalTasks))

                catalog:withWriteAccessDo("Sync Metadata Batch", function()
                    for j = i, endIndex do
                        local task = tasks[j]
                        local raw = task.raw
                        
                        -- 安全写入：只写入有效值
                        if task.rating ~= nil then raw:setRawMetadata('rating', task.rating) end
                        if task.pickStatus ~= nil then raw:setRawMetadata('pickStatus', task.pickStatus) end
                        if task.colorLabel ~= nil then raw:setRawMetadata('colorNameForLabel', task.colorLabel) end
                    end
                end)
                
                syncedCount = syncedCount + (endIndex - i + 1)
                -- 让出 CPU 片段时间，保持界面响应
                LrTasks.yield()
            end

            -- 结果报告
            progress:done()
            
            local msg = string.format("同步完成！\n成功: %d 张\n无 RAW 对应: %d 张", syncedCount, #missingRawList)
            if #missingRawList > 0 then
                -- 如果失败太多，只显示前 10 个文件名，避免弹窗过长
                local displayList = {}
                for k = 1, math.min(#missingRawList, 10) do
                    table.insert(displayList, missingRawList[k])
                end
                if #missingRawList > 10 then
                    table.insert(displayList, "... 以及其他 " .. (#missingRawList - 10) .. " 个文件")
                end
                msg = msg .. "\n\n未找到 RAW 的文件:\n" .. table.concat(displayList, "\n")
            end
            
            LrDialogs.message(LOC "$$$/RawSync/Done=完成", msg, "info")

        end) -- end async task
    end)
end

--------------------------------------------------------------------------------
-- 导出给 Info.lua 调用的入口函数
--------------------------------------------------------------------------------

function RawSync.runSyncFlags(context)
    executeSync("flags")
end

function RawSync.runSyncRatings(context)
    executeSync("ratings")
end

function RawSync.runSyncColors(context)
    executeSync("colors")
end

function RawSync.runSyncAll(context)
    executeSync("all")
end

return RawSync