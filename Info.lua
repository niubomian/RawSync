return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'com.github.niubomian.rawsync',
    LrPluginName = LOC "$$$/RawSync/PluginName=RawSync",
    LrPluginInfoUrl = "http://www.github.com/niubomian/rawsync",
    
    -- 版本号管理
    VERSION = { major=1, minor=0, revision=0, build="20260109" },

    -- 菜单项定义
    LrExportMenuItems = {
        {
            title = LOC "$$$/RawSync/SyncFlags=同步旗标 (Flags)",
            file = 'RawSync.lua',
            startFunction = 'runSyncFlags',
        },
        {
            title = LOC "$$$/RawSync/SyncRatings=同步星标 (Ratings)",
            file = 'RawSync.lua',
            startFunction = 'runSyncRatings',
        },
        {
            title = LOC "$$$/RawSync/SyncColors=同步色标 (Color Labels)",
            file = 'RawSync.lua',
            startFunction = 'runSyncColors',
        },
        {
            title = LOC "$$$/RawSync/SyncAll=同步全部元数据 (All)",
            file = 'RawSync.lua',
            startFunction = 'runSyncAll',
        },
    },
}