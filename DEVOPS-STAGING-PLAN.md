# DevOps · staging — מצב נמדד, תיקון היקף, וחסם אחד
**03/10/2026 · נמדד מול שני הפרויקטים, לא מהדיווח**

---

## 1. ✅ `auth_users` — הוכח. B1 סגור

שורת הבוקר ב-`backups/log.txt`:

```
2026-10-03  215326 bytes  r2=skipped  migrations=67 head=20261002221422 tables=18 nonzero=14 auth_users=13
```

**הטענה רצה בפעם הראשונה ועברה.** מעכשיו כל לילה מתעד אם המסד שבגיבוי
הוא מסד שאפשר להתחבר אליו, ולא רק מסד שיש בו נתונים.

---

## 2. staging — אומת אצלי

| | פרודקשן | staging |
|---|---|---|
| ref | `rkmjggormlxcvzuqedig` | `sjwkfhqsqpxknlfncbbq` |
| אזור | eu-central-1 | **ap-northeast-1** |
| Postgres | **17.6.1.166** | **17.11.0.002** |
| סכימת `public` | 18 טבלאות | **0 — ריק** |
| `auth` | 27 טבלאות · 82 מיגרציות | **27 · 82 — זהה** |

**שני פערים, ושניהם מקובלים — אבל שיהיו כתובים:**
- **האזור** — הוכרע שנשאר. מוסכם: נתוני דמה בלבד, ולכן אין משמעות לפרטיות.
- **גרסת Postgres משנית** — 17.6 מול 17.11. שחזור סכימה מ-17.6 לתוך
  17.11 תקין (קדימה), אבל **staging אינו עותק מדויק.** לא חוסם; נרשם
  כדי שלא ייוחס לו דיוק שאין לו.

**ומה שבדקתי ולא התממש:** חששתי שסכימת `auth` ב-staging חדשה יותר
ותשבור את תוכנית ה-Passkeys. **לא.** שתיהן 27 טבלאות ו-82 מיגרציות,
ובשתיהן `auth.webauthn_credentials` ו-`auth.webauthn_challenges`
קיימות. **Passkeys אפשריים בשני הצדדים.**

---

## 3. ‼ תיקון להיקף: לא משחזרים `auth` ו-`storage`

ההנדאוף אומר "auth ו-storage: סכימה בלבד". **אני ממליץ לא לגעת בהן
בכלל**, ולא מתוך עצלות:

- **staging כבר מכיל אותן, זהות** (נמדד למעלה). אין מה להעביר.
- הן מנוהלות על ידי Supabase. שחזור סכימה לתוכן יכול להתנגש עם מה
  ש-GoTrue ו-Storage מצפים לו, **ולשבור את ההתחברות ב-staging** — כלומר
  לשבור בדיוק את מה שבאנו לבדוק.

**הסכימות שעוברות, ורק הן:**

```
public · private · supabase_migrations
```

כל השאר (`auth`, `storage`, `realtime`, `vault`, `extensions`,
`graphql*`) קיימות בכל פרויקט Supabase חדש ואינן שלנו.

**הרחבות:** בפרודקשן `postgis`, `pgcrypto`, `uuid-ossp` ו-
`pg_stat_statements` יושבות ב-`extensions`, ו-`supabase_vault` ב-`vault`.
ב-staging יש להתקין את השלוש הראשונות **באותה סכימה**, אחרת
`extensions.geography` לא יימצא — בדיוק הכשל שהפיל את תרגיל השחזור
ב-28/09 (מלכודת 18).

---

## 4. ‼ החסם: `pg_dump` דורש סיסמה, ואני לא מחזיק סיסמאות

`pg_dump --schema-only` מצריך מחרוזת חיבור עם סיסמה. **היא סוד ב-GitHub,
ואיני קורא אותה ואיני מעביר אותה.** זה לא סירוב — זה אותו כלל שבגללו
ה-VAPID והסודות עברו דרך המייסד.

**הפתרון, ואין בו שום עלות ושום סוד שעובר דרכי:** הפעולה רצה **בתוך
GitHub Actions**, איפה שהסוד כבר גר.

```
.github/workflows/staging-refresh.yml   (workflow_dispatch בלבד)

  1. PGBIN=/usr/lib/postgresql/17/bin        ← כמו בגיבוי; ב-PATH יש 16
  2. pg_dump --schema-only --no-owner \
       --schema=public --schema=private --schema=supabase_migrations \
       "$SUPABASE_DB_URL"  >  schema.sql
  3. create extension if not exists postgis|pgcrypto|"uuid-ossp"
       with schema extensions            ← על staging
  4. psql -v ON_ERROR_STOP=1 "$STAGING_DB_URL" -f schema.sql
  5. ארבע בדיקות הזהות (§5) — נכשל ⇒ הריצה אדומה
```

**מה שצריך ממך/מהמייסד: סוד אחד חדש — `STAGING_DB_URL`** (Session
pooler של `sjwkfhqsqpxknlfncbbq`, עם **`postgres.sjwkfhqsqpxknlfncbbq`**
כשם המשתמש — אותה מלכודת שהפילה שבעה לילות).

**למה דרך Actions ולא ידנית:** פרודקשן ימשיך לזוז. זה הופך "לרענן את
staging" לכפתור, במקום לטקס ידני שייעשה פעם אחת ויירקב.

**ובינתיים אני לא תקוע:** נתוני הייחוס והדמה (סעיפים 2–3 בהנדאוף)
נכנסים דרך `apply_migration`, שאינו דורש סיסמה. אתחיל בהם ברגע
שהסכימה שם.

---

## 5. ארבע בדיקות הזהות — הערכים הצפויים, נמדדו עכשיו

כדי שהבדיקה לא תיכתב מהזיכרון, אלה הערכים מהפרודקשן **היום**:

| בדיקה | ערך בפרודקשן |
|---|---|
| `anon_fns` | **0** |
| `pg_get_functiondef(send_details)` מכיל `full` | **true** |
| `profiles_read` qual | **`private.may_see_profile(id)`** |
| טבלאות ב-`public` | **18** |
| פונקציות ב-`private` | **27** |
| מבחן שלמות Q5 | להריץ בשני הצדדים ולהשוות — אצל QA |

**staging שלא מחזיר את החמישה האלה — משקר, ואין להסיק ממנו דבר.**

---

## 6. מה פתוח אצלי, לפי סדר

| # | מה | ממתין ל |
|---|---|---|
| 1 | `staging-refresh.yml` | אישורך לדחיפה ל-PROD + הסוד `STAGING_DB_URL` |
| 2 | נתוני ייחוס + דמה ב-staging | שסעיף 1 ירוץ |
| 3 | Auth ב-staging: Confirm email OFF, Passkeys ON | אחרי 2. RP ID — אחרי שה-Worker של staging קיים |
| 4 | Worker שני ל-staging | שם: **לא** `round-field-973f`. אציע שם ואקבל אישור |
| 5 | Push: `sw.js`, `manifest`, `push-notify` | — ממשיך במקביל |
| 6 | P7 מסמכי אבטחת מידע | — |

---

## בלוק חפיפה

**מה אומת, ואיך:** שתי הגרסאות, האזורים והסטטוס — `list_projects`.
ריקנות `public` ב-staging וזהות `auth` — `list_tables` על staging.
ארבעת העוגנים, ההרחבות ורשימת הסכימות — `execute_sql` קריאה בלבד על
הפרודקשן. שורת `auth_users` — מ-`backups/log.txt` ב-main, כלומר מהפלט
שהריצה עצמה כתבה.

**מה לא נעשה:** לא נגעתי בפרודקשן ולא ב-staging — אפס כתיבות. לא
יצרתי Worker. לא קראתי ולא ביקשתי שום סיסמה.
