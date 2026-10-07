# הכרעות Tech Lead — 03/10/2026
**על:** `DEV-HANDOFF-BETA6-GATE` · `QA-ROUND-U-PHASE1` · `DEVOPS-SPEC-API-PII` · ריצת הגיבוי של הבוקר

```
--- מצב כל המחלקות, 03/10/2026 12:10 ---
מסד:    ראש sec02a_my_businesses · anon_fns 0 · my_businesses חי (נבדק) · נשאר ל-beta-6 רק SEC-02b (revoke עמודות)
קוד:    app.html 256,982 · md5 2855FCDD40FC · בלי BOM · CSP MATCH · חי: beta-5
עיצוב:  בעבודה (הרשמה לפי הדמו)
QA:     worker 18G/5R · mixedbiz 3/3 · closedbiz 3/3 · terms 220 ירוקה
DevOps: ✅ auth_users=13 בגיבוי (03/10) · אפיון /api/pii נמסר
מייסד:  ליצור פרויקט staging ב-Dashboard ולמסור ref
--- סוף מצב ---
```

## בקול
- **QA תפסה סדר הפוך שלי:** כתבתי "מיגרציה ואז לקוח", ואז אישרתי לקוח שקורא לפונקציה שלא הייתה קיימת. אצל מעסיק זה היה נראה כך: העסק שלו נעלם, ומוצע לו לפתוח חדש — כלומר כפילות.
  - **ושני ירוקים-ריקים שלך, שתפסת בעצמך.** "אפס מתוך אפס" נכתב עכשיו ככלל לכל הצוות (למטה).
- **DevOps — אפיון שאין לי מה להוסיף לו.** "ה-Worker אינו גבול הרשאה" הוא בדיוק העיקרון. בלי `service_role`, ‏JWKS, והפרדה בין ה-pepper למפתח.
- **הגיבוי מוכח:** `auth_users=13` בשורה של 03/10. **B1 סגור עד הסוף.**

## ההכרעה המרכזית: SEC-02 מפוצל שוב
- **`sec02a_my_businesses` — הוחל עכשיו**, תוספת בלבד:
  - המייסד: שורה אחת עם טלפון.
  - זר: 0.
  - anon: אין הרשאת הרצה.
  - beta-5 החי לא קורא לה, ולכן אין השפעה.
- **בחלון של beta-6 נשאר רק SEC-02b:** ה-revoke על העמודות. מעכשיו הלקוח של beta-6 תקין **גם לפני וגם אחרי** ה-revoke. סיכון הסדר נעלם.

## ל-Developer
| נושא | הכרעה |
|---|---|
| `icon-bell` | **מאושר** |
| המטריצה | 8/12 מאושרים. **ארבעת תאי מסך העסק — עכשיו אפשר:** `my_businesses` קיימת במסד, ול-QA כבר יש פייק (`fake-sb.js:289`) |
| תנאי 3 | **מאושר: 18/23** עם אותן חמש אדומות. התנאי הוא סט האדומות, לא המונה |
| **‼ בליעת שגיאה** | `loadBiz`: `const { data:bs } = await sb.rpc(...)` בלי `error`. **שגיאה = הודעה ("לא ניתן לטעון את העסקים כרגע") + כפתור נסה שוב. אף פעם לא `newBizScreen`.** אותו כלל לכל `rpc` שמחליט איזה מסך מוצג: כשל ≠ ריק |
| `fake-o1.js` | **הקובץ של QA (`harness/*`) — פעם שנייה.** אל תתקן אותו. QA מחליטה אם `O1-HARNESS-EMPTY` עוד חי, ואם כן — היא מעדכנת אותו ל-UMD |
| **הבא** | בליעת השגיאה ← ארבעת התאים ← החפיפה שסוגרת את השער |

## ל-QA
| נושא | הכרעה |
|---|---|
| הממצא | **מאומץ ותוקן בשרת** (sec02a). טענה חדשה: `rpc` שנכשל ב-`loadBiz` לא מוביל ל-`newBizScreen` (פייק שמחזיר `error`). הוכחת נפילה על `2855FCDD40FC` |
| ירוק-ריק | **נכנס כחוק לכל הצוות:** כל טענה מסוג "כמה מתוך" דורשת **מכנה גדול מאפס**, ואומרת אותו בפלט |
| `fake-o1.js` / `O1-HARNESS-EMPTY.html` | שלך. **להחליט:** לעדכן ל-UMD או לסמן כמת |
| אחרי SEC-02b | 42501 על `businesses.phone`, ו-4→0 |

## ל-DevOps
| נושא | הכרעה |
|---|---|
| האפיון | **מאושר כלשונו**, כולל שמונת הסעיפים |
| JWKS | **אומת אצלי:** בפרויקט יש מפתח `ES256` ב-`/auth/v1/.well-known/jwks.json`. אימות אסימטרי אפשרי בלי סוד של Supabase ב-Worker |
| staging | **ההמלצה שלך: המייסד יוצר ב-Dashboard ומוסר רק את ה-ref.** סיסמת המסד לא עוברת דרך אף סוכן |
| הסודות | המייסד מדביק את שניהם ב-Cloudflare (מפתח הצפנה, pepper). **pepper נוצר פעם אחת ונשמר גם בכספת של המייסד** — אובדן שלו = כל כתובות הכניסה |
| נספח (Push כללי) | נכון — הנוסח הכללי מבטל את הבעיה במבנה, לא בזהירות |

**אצלי, מתוך §8:** `get_contact_cipher` + `audit_log` + `cipher`/`phone_hmac` בסכימה. **על staging, ברגע שיש ref.**

## ✅ staging קיים — 03/10
`mishmeret-staging` · ref **`sjwkfhqsqpxknlfncbbq`** · ACTIVE_HEALTHY · Postgres 17.11 · ריק (0 טבלאות). נמדד.

**שתי עובדות, ושתי הכרעות:**
1. **האזור הוא `ap-northeast-1` (טוקיו), לא פרנקפורט.** **נשאר.** ב-staging יש נתוני דמה בלבד, ולכן האזור לא משנה פרטיות ולא בדיקה. ליצור מחדש לא מרוויח כלום. **הכלל נעול: אף שורה אמיתית לא עוברת ל-staging, לעולם** — לא דאמפ עם נתונים, ולא "רק משתמש אחד".
2. **ריפליי של 68 המיגרציות ייתן סכימה שגויה.** S5 (`send_details`) ו-SEC-01 (`profiles_read`, `may_see_profile`, ברירות המחדל) הוחלו דרך SQL Editor ואינם בהיסטוריה. ריפליי יחזיר ל-staging בדיוק את הגרסאות שדולפות.

```
--- HANDOFF TO: DevOps · staging ---
FOR YOU:
 1. סכימה: pg_dump --schema-only מהפרודקשן (אותו PGBIN 17 ואותו תרגיל כמו בגיבוי:
    postgis ל-extensions, סכמות מראש, supabase_realtime) → שחזור ל-sjwkfhqsqpxknlfncbbq.
    **בלי נתונים.** auth ו-storage: סכימה בלבד.
 2. נתוני ייחוס בלבד (לא אישיים): terms · cities · city_names · role_categories. --data-only לטבלאות האלה בלבד.
 3. דמה: 3 עסקים (אחד סגור), 6 משמרות, 5 עובדים — משתמשים חדשים שנוצרים ב-staging. אף טלפון אמיתי.
 4. Auth ב-staging: Confirm email = OFF (כמו בפרודקשן) · Passkeys = ON, עם RP ID של ה-Worker של staging.
 5. אימות שזה אותו מסד: מבחן השלמות (Q5) · anon_fns = 0 · `pg_get_functiondef` של send_details מכיל 'full'
    · profiles_read = may_see_profile(id). **ארבעתם — אחרת staging משקר.**
 6. Worker שני ל-staging (static) — שם נפרד, ואף פעם לא round-field-973f.
MUST KNOW: מפתח ה-service של staging אינו של הפרודקשן, וגם הוא לא עובר בצ'אט.
           מה שנבדק ב-staging מוחל בפרודקשן כמיגרציה רשומה — לא ב-SQL Editor.
--- END ---
```
**כלל חדש בעקבות זה:** מעכשיו **כל** שינוי בפרודקשן נכנס כמיגרציה רשומה (`apply_migration`). SQL Editor רק כשאין ברירה, ואז הוא נרשם גם כקובץ ב-`docs/` **וגם** מוחל כמיגרציה ב-staging.

## על `DEVOPS-STAGING-PLAN` — 03/10 12:15
**בקול: צדקת, והבריף שלי היה שגוי.** "auth ו-storage: סכימה בלבד" היה שובר את ההתחברות ב-staging. נמדד אצלך: שתיהן כבר זהות (27 טבלאות, 82 מיגרציות, `webauthn_*` קיימות).

| נושא | הכרעה |
|---|---|
| היקף | **רק `public` · `private` · `supabase_migrations`.** auth/storage — לא נוגעים |
| הרחבות | `postgis` · `pgcrypto` · `uuid-ossp` ב-`extensions` **לפני** השחזור (מלכודת 18) |
| `supabase_migrations` | סכימה **+ השורות של `schema_migrations`** (היסטוריה, לא מידע אישי), כדי שבדיקת "ראש" תהיה זהה בשני הצדדים |
| 17.6 מול 17.11 | **נרשם ומקובל.** staging אינו עותק מדויק, ולא נייחס לו כזה |
| `staging-refresh.yml` | **מאושר לדחיפה ל-main**, עם שלושה שומרים חובה, כל אחד נכשל עם הודעה: |
| | 1. `STAGING_DB_URL` חייב להכיל `sjwkfhqsqpxknlfncbbq` |
| | 2. `SUPABASE_DB_URL` חייב להכיל `rkmjggormlxcvzuqedig` **ולשמש רק את `pg_dump`.** שום `psql` לא רץ מולו |
| | 3. אם שני ה-URL-ים שווים — עצירה |
| | **לעולם לא כותבים לפרודקשן מה-workflow הזה.** מסור כ-diff/קובץ, ואני דוחף (plumbing) |
| בדיקות הזהות | **חמש הבדיקות שלך מחייבות:** anon_fns=0 · `full` ב-send_details · `may_see_profile(id)` · 18 טבלאות · 27 פונקציות ב-private. אדום = staging לא בשימוש |
| נתוני דמה | דרך `apply_migration` על staging — **מאושר.** שם מיגרציה מתחיל ב-`staging_seed_` |
| Worker של staging | **השם חייב להכיל `staging`.** הצע, ואני מאשר |

## `staging-refresh.yml` — נדחף ל-main, 03/10 12:30 (`bb32de1`)
**נבדק לפני הדחיפה:**
- השומרים במקומם: staging≠פרודקשן, ref מוקלד ביד, pooler, `postgres.<ref>`.
- **אין שום `psql` מול `SUPABASE_DB_URL`** — רק `pg_dump`.
- בלי BOM ובלי CRLF.
- הקובץ ב-main זהה למסירה.

**שלושה המשכים ל-DevOps, אף אחד מהם לא חוסם:**
1. **השורות של `schema_migrations`** לא עוברות (schema-only). הוסף `pg_dump --data-only --table=supabase_migrations.schema_migrations`. כך "ראש" זהה בשני הצדדים.
2. **storage של staging ריק:** אין buckets `biz`/`avatars` ואין מדיניות. תמונות לא נבדקות שם עד שיתווספו. בלי נתונים — רק הגדרות.
3. **הריצה הראשונה עלולה ליפול על `CREATE SCHEMA public` כפול** (הצעד יוצר אותה, ואולי גם הדאמפ). אם כן — להסיר את היצירה מהצעד. כשל ב-staging לא נוגע בפרודקשן.

**הרצה (המייסד):**
1. Actions → staging-refresh → Run workflow.
2. להקליד `sjwkfhqsqpxknlfncbbq` → Run.
3. ירוק = staging זהה. אדום — DevOps קורא את הלוג ומתקן.

**19:15 — ריצה #1 נפלה, בדיוק על המשך 3:** `schema "public" already exists`.
- **מה זה אומר טוב:** השומרים והסודות עברו. הריצה הגיעה עד שלב החלת הסכימה, ולכן `STAGING_DB_URL` מוגדר ותקין.
- **התיקון של DevOps אומת ונדחף (`9c5b8db`):**
  - הדאמפ יוצר את `public`, והצעד כבר לא.
  - הרשאת usage ניתנת מחדש אחרי ההחלה.
  - בדיקת זהות שישית: `anon` ו-`authenticated` עם usage על `public`.
- staging כרגע ריק (0 טבלאות). **מריצים שוב.**
- **ל-DevOps:** תיקון בלי קובץ חפיפה הוא תיקון שלא קרה. שתי שורות ב-`docs/` בפעם הבאה, גם לתיקון קטן.

**19:40 — ריצה #2 אדומה. אובחן מהמסד, לא מהלוג, ותוקן (`22f1314`):**
- **מה כן עבר (נמדד ב-staging):** 18 טבלאות · 27 פונקציות ב-private · anon_fns=0 · `full` ב-send_details · `may_see_profile` · usage · 0 שורות אישיות.
- **מה הפיל:** הדאמפ נושא שורות ברירת מחדל של הפלטפורמה (`FOR ROLE supabase_admin`). ל-postgres אסור לשנות אותן. שוחזר אצלי: `42501 permission denied to change default privileges`.
- **ממצא שהריצה האדומה חשפה, וחשוב ממנה:** ב-staging **אין** ברירות מחדל לפונקציות. `pg_dump --schema` לא נושא את השורה הגלובלית של SEC-01, ולכן **מלכודת 2 הייתה פתוחה ב-staging.** הוכחת נפילה: פונקציה חדשה → anon=true.
- **התיקון:**
  - השורות של הפלטפורמה מדולגות.
  - ברירות המחדל של הפרודקשן מוחלות במפורש.
  - **עוגן שביעי:** פונקציה חדשה = `anon=false,authenticated=true`. **נמדד זהה בפרודקשן ובאחרי-התיקון ב-staging.**
- **נגעתי בקובץ של DevOps** (`staging-refresh.yml`) כי המייסד חיכה מול מסך אדום. **הוא חוזר אליך** — תעבור על השינוי.

## למייסד — סוד אחד ב-GitHub (`STAGING_DB_URL`)
1. Supabase → **mishmeret-staging** → **Connect** → **Session pooler** → להעתיק את ה-URI.
2. לוודא ששם המשתמש בו הוא **`postgres.sjwkfhqsqpxknlfncbbq`**, ולהחליף את `[YOUR-PASSWORD]` בסיסמה ששמרת.
3. GitHub → **mishmeret-app** → Settings → Secrets and variables → Actions → **New repository secret**.
4. שם: `STAGING_DB_URL`. ערך: ה-URI. ‏Add secret.

**הסיסמה לא עוברת דרך אף סוכן.**

## למייסד — דבר אחד (מוקדם יותר)
**ליצור פרויקט staging:**
- [supabase.com/dashboard](https://supabase.com/dashboard) → New project.
- שם: `mishmeret-staging`. אזור: Central EU (Frankfurt). תוכנית: Free.
- סיסמת מסד — **אתה בוחר ושומר אצלך.**
- למסור רק את ה-Reference ID. הוא מופיע בכתובת: `/project/<ref>`.

עלות: 0.
