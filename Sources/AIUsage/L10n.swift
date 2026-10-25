import Foundation

/// Order matches the translation arrays below: en, ru, es, zh, de.
enum Lang: String, CaseIterable, Identifiable {
    case en, ru, es, zh, de
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .es: return "Español"
        case .zh: return "中文"
        case .de: return "Deutsch"
        }
    }
    var index: Int { Lang.allCases.firstIndex(of: self)! }

    static func systemDefault() -> Lang {
        for code in Locale.preferredLanguages {
            if let l = Lang(rawValue: String(code.prefix(2))) { return l }
        }
        return .en
    }
}

enum L10n {
    /// Set by Preferences whenever the language changes.
    static var current: Lang = .en

    static func t(_ key: String) -> String {
        strings[key]?[current.index] ?? key
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// "2d 3h" style duration in the current language.
    static func duration(days d: Int, hours h: Int, minutes m: Int) -> String {
        let u = units[current.index]
        let sep = current == .zh ? "" : " "
        if d >= 10 { return "\(d)\(u.0)" }
        if d > 0 { return "\(d)\(u.0)\(sep)\(h)\(u.1)" }
        if h > 0 { return "\(h)\(u.1)\(sep)\(m)\(u.2)" }
        return "\(max(m, 1))\(u.2)"
    }

    private static let units: [(String, String, String)] = [
        ("d", "h", "m"), ("д", "ч", "м"), ("d", "h", "min"), ("天", "小时", "分"), ("T", "Std", "Min")
    ]

    // en, ru, es, zh, de
    private static let strings: [String: [String]] = [
        "title": ["AI usage", "Расход ИИ", "Uso de IA", "AI 用量", "KI-Nutzung"],
        "noServices": ["No AI services selected", "ИИ-сервисы не выбраны", "Ningún servicio de IA seleccionado", "未选择 AI 服务", "Keine KI-Dienste ausgewählt"],
        "chooseServices": ["Choose services…", "Выбрать сервисы…", "Elegir servicios…", "选择服务…", "Dienste wählen…"],
        "helpRefresh": ["Click to refresh", "Нажмите, чтобы обновить", "Haz clic para actualizar", "点击刷新", "Zum Aktualisieren klicken"],
        "updating": ["Updating…", "Обновление…", "Actualizando…", "正在更新…", "Aktualisiere…"],
        "notUpdated": ["Not updated", "Не обновлено", "Sin actualizar", "未更新", "Nicht aktualisiert"],
        "updatedNow": ["Updated now", "Обновлено сейчас", "Actualizado ahora", "刚刚更新", "Gerade aktualisiert"],
        "updatedMin": ["Updated %d min ago", "Обновлено %d мин назад", "Actualizado hace %d min", "%d 分钟前更新", "Vor %d Min. aktualisiert"],
        "updatedHour": ["Updated %d h ago", "Обновлено %d ч назад", "Actualizado hace %d h", "%d 小时前更新", "Vor %d Std. aktualisiert"],
        "settings": ["Settings", "Настройки", "Ajustes", "设置", "Einstellungen"],
        "settingsMenu": ["Settings…", "Настройки…", "Ajustes…", "设置…", "Einstellungen…"],
        "quit": ["Quit", "Выйти", "Salir", "退出", "Beenden"],
        "remaining": ["remaining", "осталось", "restante", "剩余", "übrig"],
        "loading": ["Loading…", "Загрузка…", "Cargando…", "加载中…", "Lädt…"],
        "day": ["Daily", "День", "Día", "每日", "Tag"],
        "week": ["Weekly", "Неделя", "Semana", "每周", "Woche"],
        "sub": ["Plan", "Подписка", "Plan", "订阅", "Abo"],
        "resetIn": ["Resets in %@", "Сброс через %@", "Reinicio en %@", "%@后重置", "Reset in %@"],
        "payIn": ["Payment %@", "Оплата %@", "Pago %@", "付款 %@", "Zahlung %@"],
        "resetting": ["Resetting…", "Сбрасывается…", "Restableciendo…", "正在重置…", "Wird zurückgesetzt…"],
        "payDue": ["Payment due", "Пора платить", "Pago pendiente", "即将付款", "Zahlung fällig"],
        "resetUnknown": ["Reset time unknown", "Время сброса неизвестно", "Hora de reinicio desconocida", "重置时间未知", "Zeitpunkt unbekannt"],
        "dateUnknown": ["Date unknown", "Дата неизвестна", "Fecha desconocida", "日期未知", "Datum unbekannt"],
        "notAvailable": ["Not available", "Недоступно", "No disponible", "不可用", "Nicht verfügbar"],

        "servicesHeader": ["AI services", "ИИ-сервисы", "Servicios de IA", "AI 服务", "KI-Dienste"],
        "servicesFooter": [
            "Only ticked services appear in the widget. A service becomes available once you're signed in to its app or command-line tool on this Mac. More services are coming soon.",
            "В виджете показываются только отмеченные сервисы. Сервис становится доступен, когда вы вошли в его приложение или терминальную программу на этом Маке. Другие сервисы скоро появятся.",
            "En el widget solo aparecen los servicios marcados. Un servicio está disponible cuando has iniciado sesión en su app o herramienta de línea de comandos en este Mac. Pronto habrá más servicios.",
            "小组件只显示已勾选的服务。在这台 Mac 上登录其应用或命令行工具后，服务即可使用。更多服务即将推出。",
            "Im Widget erscheinen nur ausgewählte Dienste. Ein Dienst ist verfügbar, sobald du dich in seiner App oder seinem Kommandozeilentool auf diesem Mac angemeldet hast. Weitere Dienste folgen."],
        "where": ["Where to show", "Где показывать", "Dónde mostrar", "显示位置", "Anzeigeort"],
        "desktop": ["Desktop widget", "Виджет на рабочем столе", "Widget en el escritorio", "桌面小组件", "Widget auf dem Schreibtisch"],
        "onTop": ["Keep above other windows", "Поверх других окон", "Sobre otras ventanas", "置于其他窗口之上", "Über anderen Fenstern"],
        "notch": ["Show when hovering the notch", "Показывать при наведении на «челку»", "Mostrar al pasar sobre el notch", "悬停在刘海上时显示", "Beim Überfahren der Notch anzeigen"],
        "menuNote": ["The menu bar icon opens the window on click.", "Иконка в строке меню открывает окно по клику.", "El icono de la barra de menús abre la ventana con un clic.", "点击菜单栏图标可打开窗口。", "Das Menüleisten-Symbol öffnet das Fenster per Klick."],
        "updatesHeader": ["Updates", "Обновление", "Actualización", "更新", "Aktualisierung"],
        "frequency": ["Frequency", "Частота", "Frecuencia", "频率", "Häufigkeit"],
        "refreshNow": ["Refresh now", "Обновить сейчас", "Actualizar ahora", "立即刷新", "Jetzt aktualisieren"],
        "signedIn": ["Signed in on this Mac", "Вход выполнен на этом Маке", "Sesión iniciada en este Mac", "已在此 Mac 上登录", "Auf diesem Mac angemeldet"],
        "notUpdatedYet": ["Not updated yet", "Ещё не обновлялось", "Aún sin actualizar", "尚未更新", "Noch nicht aktualisiert"],
        "lastUpdated": ["Last updated at %@", "Обновлено в %@", "Actualizado a las %@", "更新于 %@", "Aktualisiert um %@"],
        "moveToApps": ["Move the app to the Applications folder first, then try again.", "Сначала переместите приложение в папку «Программы», затем повторите.", "Mueve primero la app a la carpeta Aplicaciones y vuelve a intentarlo.", "请先将应用移到“应用程序”文件夹，然后重试。", "Bewege die App zuerst in den Ordner „Programme“ und versuche es erneut."],
        "launchAtLogin": ["Launch at login", "Запускать при входе в систему", "Abrir al iniciar sesión", "登录时启动", "Beim Anmelden starten"],
        "general": ["General", "Основные", "General", "通用", "Allgemein"],
        "language": ["Language", "Язык", "Idioma", "语言", "Sprache"],
        "checkUpdates": ["Check for Updates…", "Проверить обновления…", "Buscar actualizaciones…", "检查更新…", "Nach Updates suchen…"],
        "updateAvailable": ["Version %@ is available", "Доступна версия %@", "Hay una nueva versión: %@", "有新版本 %@", "Version %@ ist verfügbar"],
        "updateCurrent": ["You have version %@.", "У вас версия %@.", "Tienes la versión %@.", "当前版本 %@。", "Du hast Version %@."],
        "upToDate": ["You have the latest version (%@)", "У вас последняя версия (%@)", "Tienes la última versión (%@)", "已是最新版本 (%@)", "Du hast die neueste Version (%@)"],
        "updateFailed": ["Couldn't check for updates", "Не удалось проверить обновления", "No se pudo buscar actualizaciones", "无法检查更新", "Update-Suche fehlgeschlagen"],
        "download": ["Download", "Скачать", "Descargar", "下载", "Laden"],
        "later": ["Later", "Позже", "Más tarde", "稍后", "Später"],
        "version": ["Version %@", "Версия %@", "Versión %@", "版本 %@", "Version %@"],
        "hideWidget": ["Hide Desktop Widget", "Скрыть виджет", "Ocultar widget", "隐藏小组件", "Widget ausblenden"],
        "showWidget": ["Show Desktop Widget", "Показать виджет", "Mostrar widget", "显示小组件", "Widget einblenden"],

        "everyMin": ["Every minute", "Каждую минуту", "Cada minuto", "每分钟", "Jede Minute"],
        "every5": ["Every 5 minutes", "Каждые 5 минут", "Cada 5 minutos", "每 5 分钟", "Alle 5 Minuten"],
        "every15": ["Every 15 minutes", "Каждые 15 минут", "Cada 15 minutos", "每 15 分钟", "Alle 15 Minuten"],
        "every30": ["Every 30 minutes", "Каждые 30 минут", "Cada 30 minutos", "每 30 分钟", "Alle 30 Minuten"],
        "manual": ["Manual only", "Только вручную", "Solo manual", "仅手动", "Nur manuell"],

        "hintCodex": ["Run in Terminal: codex login", "Выполните в Терминале: codex login", "Ejecuta en Terminal: codex login", "在终端运行：codex login", "Im Terminal ausführen: codex login"],
        "hintClaude": ["Run in Terminal: claude, then /login", "Выполните в Терминале: claude, затем /login", "Ejecuta en Terminal: claude y luego /login", "在终端运行：claude，然后 /login", "Im Terminal ausführen: claude, dann /login"],

        "errNoConn": ["No connection", "Нет соединения", "Sin conexión", "无网络连接", "Keine Verbindung"],
        "errBadResp": ["Invalid server response", "Некорректный ответ сервера", "Respuesta del servidor no válida", "服务器响应无效", "Ungültige Serverantwort"],
        "errFormat": ["Unexpected response format", "Неожиданный формат ответа", "Formato de respuesta inesperado", "响应格式异常", "Unerwartetes Antwortformat"],
        "errHTTP": ["Server error (HTTP %d)", "Ошибка сервера (HTTP %d)", "Error del servidor (HTTP %d)", "服务器错误 (HTTP %d)", "Serverfehler (HTTP %d)"],
        "errClaudeExpired": ["Claude login expired. Run in Terminal: claude, then /login", "Вход в Claude устарел. Выполните в Терминале: claude, затем /login", "La sesión de Claude caducó. Ejecuta en Terminal: claude y luego /login", "Claude 登录已过期。在终端运行：claude，然后 /login", "Claude-Anmeldung abgelaufen. Im Terminal: claude, dann /login"],
        "errClaudeNo": ["Not signed in to Claude. Run in Terminal: claude, then /login", "Нет входа в Claude. Выполните в Терминале: claude, затем /login", "Sin sesión en Claude. Ejecuta en Terminal: claude y luego /login", "未登录 Claude。在终端运行：claude，然后 /login", "Nicht bei Claude angemeldet. Im Terminal: claude, dann /login"],
        "errKeychain": ["Couldn't save the refreshed login to Keychain. Run /login in claude", "Не удалось сохранить обновлённый вход в Связку ключей. Выполните /login в claude", "No se pudo guardar el acceso renovado en el Llavero. Ejecuta /login en claude", "无法将更新后的登录保存到钥匙串。请在 claude 中运行 /login", "Erneuerte Anmeldung konnte nicht im Schlüsselbund gespeichert werden. /login in claude ausführen"],
        "errWaitClaude": ["Waiting for Claude Code to renew its login", "Ждём, пока Claude Code обновит вход", "Esperando a que Claude Code renueve su sesión", "等待 Claude Code 更新登录", "Warte, bis Claude Code die Anmeldung erneuert"],
        "errGPTNo": ["Not signed in to ChatGPT. Run in Terminal: codex login", "Нет входа в ChatGPT. Выполните в Терминале: codex login", "Sin sesión en ChatGPT. Ejecuta en Terminal: codex login", "未登录 ChatGPT。在终端运行：codex login", "Nicht bei ChatGPT angemeldet. Im Terminal: codex login"],
        "errGPTExpired": ["ChatGPT login expired. Run Codex once", "Вход в ChatGPT устарел. Запустите Codex один раз", "La sesión de ChatGPT caducó. Ejecuta Codex una vez", "ChatGPT 登录已过期。请运行一次 Codex", "ChatGPT-Anmeldung abgelaufen. Codex einmal starten"],
        "errNoLimits": ["No limit data for this plan", "Для этого тарифа нет данных о лимитах", "Sin datos de límites para este plan", "此套餐没有限额数据", "Keine Limitdaten für diesen Tarif"],
    ]
}

/// Shorthand used throughout the UI.
func t(_ key: String) -> String { L10n.t(key) }
