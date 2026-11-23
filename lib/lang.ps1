# 0x — menu language table. English is the base; Persian overlays it.
# Technical log lines ([ok], [heal], errors) stay English by design.

function Get-Lang([string]$Code) {
    $en = @{
        menu_install = 'install'; menu_repair = 'repair'; menu_restart = 'restart'
        menu_deep = 'deep restart'; menu_status = 'status'; menu_watchdog = 'watchdog'
        menu_openoc = 'open oc'; menu_revert = 'revert'; menu_depth = 'depth reset'
        menu_logs = 'logs'; menu_backups = 'backups'; menu_quit = 'quit'
        menu_inject = 'inject'; menu_sessions = 'sessions'; menu_lang = 'language'
        custom_by = 'Custom by'; telegram = 'Telegram'; bax = 'Bax'
        any_key = 'any key to return'; cancelled = 'cancelled'
        sure_install = 'full install: backup, files, config, restart. sure? [y/N]'
        sure_repair = 'repair: re-apply chain + plugin + config. overwrite live AGENTS.md too? [y/N]'
        sure_revert = 'full revert from latest backup (files + config keys + watchdog). sure? [y/N]'
        sure_depth = 'reset all depth state? every session returns to stage 0. [y/N]'
        repaired = 'repaired — restart (3) to re-arm the plugin'
        launched = 'opencode launched'; not_on_path = 'opencode not on PATH'
        cold_started = 'opencode cold-started'; not_visible = 'process not visible after start'
        start_manual = 'opencode not on PATH — start it manually'
        depth_cleared = 'depth state cleared'; depth_cleared_all = 'depth state cleared — every session re-arms from stage 0'
        logs_hb = 'heartbeat'; logs_hb_note = '(every hook fire)'; logs_heal = 'heal log'; logs_heal_note = '(watchdog)'
        no_heartbeat = '(no heartbeat yet — make one model call in OpenCode)'; no_heal = '(no watchdog runs yet)'
        backups_none = 'no backups yet'; backups_title = 'backups'; backups_note = 'newest first — press its number to revert'
        backups_cancel = '[any other key] cancel'; reverting = 'reverting from'
        watchdog_on = 'watchdog ON — the chain heals itself at every logon'; watchdog_off = 'watchdog OFF'
        status_unavailable = 'status unavailable'
        inject_title = 'INJECT AI — console'; inject_preview = 'preview'; inject_lint = 'lint'
        inject_stats = 'stats'; inject_payloads = 'payloads'; inject_profiles = 'profiles'
        inject_debug = 'debug toggle'; inject_sim = 'simulate'; inject_test = 'selftest'
        inject_unit = 'unit test'; inject_back = 'back'
        sessions_title = 'sessions'; sessions_none = 'no sessions tracked yet'
        sessions_reset = 'press its number to reset · any other key cancels'
        session_reset_q = 'reset this session? [y/N]'; session_reset_ok = 'session reset'
        lang_switched = 'language switched'
        inject_profile = 'profile'; inject_payloads_n = 'payloads'; inject_last = 'last'; inject_scrubs = 'scrubs'
    }
    $fa = @{
        menu_install = 'نصب'; menu_repair = 'تعمیر'; menu_restart = 'ری‌استارت'
        menu_deep = 'ری‌استارت عمیق'; menu_status = 'وضعیت'; menu_watchdog = 'نگهبان'
        menu_openoc = 'بازکردن OC'; menu_revert = 'برگشت'; menu_depth = 'ریست عمق'
        menu_logs = 'لاگ‌ها'; menu_backups = 'بکاپ‌ها'; menu_quit = 'خروج'
        menu_inject = 'تزریق'; menu_sessions = 'سشن‌ها'; menu_lang = 'زبان'
        custom_by = 'ساخته‌شده توسط'; telegram = 'تلگرام'; bax = 'باکس'
        any_key = 'هر کلیدی برای بازگشت'; cancelled = 'لغو شد'
        sure_install = 'نصب کامل: بکاپ، فایل‌ها، کانفیگ، ری‌استارت. مطمئنی؟ [y/N]'
        sure_repair = 'تعمیر: چین و پلاگین و کانفیگ دوباره اعمال شود. AGENTS.md زنده هم بازنویسی شود؟ [y/N]'
        sure_revert = 'برگشت کامل از آخرین بکاپ (فایل‌ها + کلیدهای کانفیگ + نگهبان). مطمئنی؟ [y/N]'
        sure_depth = 'همه‌ی state عمق ریست شود؟ هر سشن از stage 0 شروع می‌کند. [y/N]'
        repaired = 'تعمیر شد — ری‌استارت (3) برای مسلح‌کردن پلاگین'
        launched = 'opencode اجرا شد'; not_on_path = 'opencode روی PATH نیست'
        cold_started = 'opencode کولد‌استارت شد'; not_visible = 'پروسه بعد از استارت دیده نشد'
        start_manual = 'opencode روی PATH نیست — دستی اجرا کن'
        depth_cleared = 'state عمق پاک شد'; depth_cleared_all = 'state عمق پاک شد — هر سشن از stage 0 مسلح می‌شود'
        logs_hb = 'هارت‌بیت'; logs_hb_note = '(هر شلیک هوک)'; logs_heal = 'لاگ ترمیم'; logs_heal_note = '(نگهبان)'
        no_heartbeat = '(هنوز هارت‌بیتی نیست — یک بار در OpenCode مدل را صدا بزن)'; no_heal = '(هنوز نگهبان اجرا نشده)'
        backups_none = 'هنوز بکاپی نیست'; backups_title = 'بکاپ‌ها'; backups_note = 'جدیدترین اول — شماره‌اش را بزن برای برگشت'
        backups_cancel = '[هر کلید دیگر] لغو'; reverting = 'برگشت از'
        watchdog_on = 'نگهبان روشن — چین در هر لاگون خودش را ترمیم می‌کند'; watchdog_off = 'نگهبان خاموش'
        status_unavailable = 'وضعیت در دسترس نیست'
        inject_title = 'INJECT AI — کنسول'; inject_preview = 'پیش‌نمایش'; inject_lint = 'لینت'
        inject_stats = 'آمار'; inject_payloads = 'پیلودها'; inject_profiles = 'پروفایل‌ها'
        inject_debug = 'دیباگ'; inject_sim = 'شبیه‌سازی'; inject_test = 'تست'
        inject_unit = 'تست واحد'; inject_back = 'بازگشت'
        sessions_title = 'سشن‌ها'; sessions_none = 'هنوز سشنی ثبت نشده'
        sessions_reset = 'شماره‌اش را بزن برای ریست · هر کلید دیگر لغو'
        session_reset_q = 'این سشن ریست شود؟ [y/N]'; session_reset_ok = 'سشن ریست شد'
        lang_switched = 'زبان عوض شد'
        inject_profile = 'پروفایل'; inject_payloads_n = 'پیلود'; inject_last = 'آخرین'; inject_scrubs = 'اسکراب'
    }
    $out = @{}
    $useFa = ($Code -eq 'fa')
    foreach ($k in $en.Keys) {
        if ($useFa -and $fa.ContainsKey($k)) { $out[$k] = $fa[$k] } else { $out[$k] = $en[$k] }
    }
    return ,$out
}
