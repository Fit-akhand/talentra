-- Query 12: Multilingual UI Translation Lookup with Fallback
-- Domain: messaging / master
-- Type: High-Frequency UI Key Resolution
-- Purpose: Bulk fetch interface translations for a given language code with fallback to default English.

SELECT
    keys.string_key,
    COALESCE(target.translated_text, fallback.translated_text, keys.string_key) AS resolved_ui_text,
    CASE
        WHEN target.translated_text IS NOT NULL THEN 'target_language'
        WHEN fallback.translated_text IS NOT NULL THEN 'english_fallback'
        ELSE 'key_fallback'
    END AS resolution_source
FROM (
    VALUES
        ('btn.apply_job'),
        ('nav.job_search'),
        ('label.welcome_back'),
        ('nonexistent.action_button')
) AS keys(string_key)
LEFT JOIN messaging.ui_translation target
    ON keys.string_key = target.string_key AND target.language_code = 'es'
LEFT JOIN messaging.ui_translation fallback
    ON keys.string_key = fallback.string_key AND fallback.language_code = 'en';
