fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'

name 'retry_greenscreener'
author 'Retry Studio'
version '1.0.0'
description 'Green Screen Screenshot Studio - Standalone screenshot tool for FiveM'

-- Fivemanage image hosting (set in server.cfg):
--   set retry_greenscreener_fivemanage_key "<your_api_key>"
--   set retry_greenscreener_fivemanage_endpoint "https://api.fivemanage.com/api/v3/file"   (optional, default shown)
convar_category 'retry_greenscreener' {
    'Retry Greenscreener — Image Hosting',
    {
        { 'Fivemanage API key',        'retry_greenscreener_fivemanage_key',      'CV_STRING', '' },
        { 'Fivemanage upload endpoint', 'retry_greenscreener_fivemanage_endpoint', 'CV_STRING', 'https://api.fivemanage.com/api/v3/file' },
    },
}

dependencies {
    '/server:6116',
    '/onesync',
    'ox_lib',
    'screenshot-basic',
}

shared_scripts {
    '@ox_lib/init.lua',
}

server_scripts {
    'server/main.lua',
    'server/images.lua',
    'server/screenshot.js',
}

client_scripts {
    'client/main.lua',
}

ui_page 'web/build/index.html'

files {
    'web/build/index.html',
    'web/build/assets/*.js',
    'web/build/assets/*.js.map',
    'web/build/assets/*.css',
    'data/*.json',
}

-- Stream assets (green screen prop)
this_is_a_map 'yes'
data_file 'DLC_ITYP_REQUEST' 'stream/jim_g_green_screen_v1.ytyp'

escrow_ignore {
    'data/*.json',
    'web/build/**/*',
    'web/build/index.html',
    'stream/*',
    'package.json',
    'package-lock.json',
}
