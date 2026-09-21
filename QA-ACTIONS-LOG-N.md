# QA — יומן פעולות, סבב N
**נכתב: 21/09/2026 · עבור: Tech Lead · מטרה: מעבר ביקורת על מה שעשיתי**

הקובץ הזה אינו דוח ממצאים. הממצאים ב-`QA-FINDINGS-N.md` וב-
`QA-FINDINGS-M.md`. **זה רישום של כל פעולה שביצעתי, כדי שתוכל לשחזר
אותה, לפסול אותה, או לתפוס אותי בטעות.** כל שאילתה כאן ניתנת להדבקה.

---

## 0. הצהרת מצב

| | |
|---|---|
| ראש מיגרציות בסיום | `20260921125932 board_bucket_terms` |
| `app.html` בסיום | 141,069 בתים · 21/09 16:55 |
| **כתיבות שביצעתי למסד** | **אפס** |
| קבצים שיצרתי | `QA-FINDINGS-M.md` · `QA-FINDINGS-N.md` · הקובץ הזה |
| קבצים ששיניתי | `QA-HANDOVER.md` — §4 בלבד |
| קבצים שלא נגעתי בהם | `app.html` ו-`Mishmeret-v3.html` |

**הוכחת אי-הכתיבה, לא הצהרה:** צירפתי ל-Q5 שתי שורות קבועות,
`phone_verified count` ו-`private.operators count`. שתיהן 0 בפתיחה
ו-0 בסגירה. כל קריאה ל-`verify_phone` שהרצתי עטופה ב-`begin/rollback`,
וכולן חזרו `forbidden` **לפני** ה-`update` בגוף הפונקציה — אימתתי את
מיקום ה-`return` ב-`pg_get_functiondef` לפני שהרצתי, לא אחרי.

---

## 1. רצף הפעולות, לפי סדר

| # | פעולה | כלי | תוצאה |
|---|---|---|---|
| 1 | קריאת `ROUND-N-POLISH.md` §7 | קובץ | קיבלתי N6 |
| 2 | כתיבת `QA-FINDINGS-M.md` | כתיבת קובץ | ממצאי M-2 ו-M-3 עלו לדיסק |
| 3 | ראש מיגרציות | SQL | `20260921121155` באותו רגע |
| 4 | Q5 פתיחה, 17 שורות | SQL | כולן 0 פרט ל-`address but no pin`=1 |
| 5 | גוף `verify_phone` · `unverify_phone` · `is_operator` | `pg_get_functiondef` | מיפוי מסלולי הכתיבה |
| 6 | ACL של הפונקציות · `relacl` של `operators` · `nspacl` של `private` | קטלוג | מצאתי ברירת מחדל = PUBLIC |
| 7 | אינדקסים על `profile_contacts.phone` | `pg_indexes` | `phone_conflict` הוא קוד מת |
| 8 | `private.operators` כ-`anon` | התחזות | `42501 permission denied` ✓ |
| 9 | `private.operators` כ-`authenticated` | התחזות | `42501 permission denied` ✓ |
| 10 | `is_operator` + `is_adult` כ-`anon` | התחזות | **החזירו ערך — הממצא** |
| 11 | `verify_phone` ×3 + `unverify_phone` כלא-מפעיל | התחזות | ארבעתם `forbidden` ✓ |
| 12 | `verify_phone` כ-`anon` | התחזות | `42501 permission denied for function` ✓ |
| 13 | Q5 סגירה + 2 שורות WRITE-PROOF | SQL | זהה לפתיחה |
| 14 | ACL של `public` INVOKER/anon | קטלוג | בסיס להמלצת ה-revoke |
| 15 | כתיבת `QA-FINDINGS-N.md` | כתיבת קובץ | — |
| — | **כאן קיבלתי את התיקונים שלך ב-`START-HERE.md`** | | |
| 16 | ראש מיגרציות מחדש | SQL | `20260921125932` — זז פעמיים |
| 17 | ACL של כל `private` × מספר מדיניות שמשתמשות | קטלוג | אימות הרצפה לפי פונקציה |
| 18 | `is_adult` כ-`anon` וכ-`authenticated` | התחזות | שניהם מסורבים ✓ |
| 19 | קריאת 9 טבלאות כ-`E_OWNER` וכ-`W_OTHER` | התחזות | אפס רגרסיה ✓ |
| 20 | ציטוט מדויק מגוף `verify_phone` | `regexp_split_to_table` | שורה 16 |
| 21 | סריקת `app.html` ל-N1 | grep/sed | N1 נחת |
| 22 | עדכון §4 ב-`QA-HANDOVER.md` | עריכת קובץ | N-Q1 נסגר |
| 23 | תיקון `QA-FINDINGS-N.md` | כתיבת קובץ | חומרה + טעות ה-revoke + ציטוט + N-P5 |

---

## 2. השאילתות, להדבקה

**Q5 המורחב** — הגרסה שהרצתי בפתיחה ובסגירה נמצאת בשלמותה בתעתיק
הסשן. שתי השורות שהוספתי מעבר לשלך:
```sql
union all select '+ LIVE shift located_at <> business', count(*)
  from shifts s join businesses b on b.id=s.business_id
  where s.ends_at > now() and s.located_at is distinct from b.located_at
union all select '+ phone_verified without claim', count(*)
  from profile_contacts where phone_verified and phone_claimed_at is null
```
ושתי שורות ההוכחה:
```sql
union all select 'WRITE-PROOF verified_count (must stay 0)', count(*)
  from profile_contacts where phone_verified
union all select 'WRITE-PROOF operators rows (must stay 0)', count(*)
  from private.operators
```

**רתמת ההתחזות** — הנוסח המדויק בכל בדיקה:
```sql
begin;
select set_config('request.jwt.claims',
       '{"sub":"<UUID>","role":"authenticated"}', true);
set local role authenticated;
select current_user, auth.uid();   -- שער: חייב authenticated + ה-uuid
-- …
rollback;
```
ל-`anon`: `set local role anon;` בלי `set_config`.

**רצפת `private`, לאימות חוזר אחרי כל מיגרציה:**
```sql
select p.proname,
       coalesce(array_to_string(p.proacl,' | '),'*** DEFAULT = PUBLIC ***') acl,
       (select count(*) from pg_policies pol
         where pol.schemaname='public'
           and (coalesce(pol.qual,'')||' '||coalesce(pol.with_check,''))
               like '%'||p.proname||'%') policies_using
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='private' order by 3 desc, 1;
```
**העמודה `policies_using` היא מה שהחסיר לי בפעם הראשונה.** היא נשארת
בתיק.

---

## 3. איפה טעיתי, ומה השתנה בשיטה

**טעות 1 — המלצתי `revoke ... from all functions in schema private`
וקראתי לזה בטוח.** בדקתי `SECURITY INVOKER` ובדקתי טריגרים. **לא
בדקתי `pg_policies`.** מדיניות RLS היא מסלול קריאה שלישי, והיא מוערכת
בתור התפקיד השואל — אחת-עשרה מדיניות היו נשברות על חמש טבלאות.

**מה השתנה:** בדיקת שטח קריאה של פונקציה כוללת מעכשיו שלושה מקורות,
לא אחד — `pg_proc` (מי קורא), `pg_trigger` (מי מפעיל), `pg_policies`
(מי מעריך). השאילתה בסעיף 2 מקודדת את זה.

**טעות 2 — ניפוח חומרה.** כתבתי "דליפה פעילה לכל האינטרנט" על סמך
הרשאה ברמת SQL, בלי לבדוק שה-API בכלל חושף את `private`. הוא לא.
זו הייתה הרשאה שגויה, לא ניצולת מרחוק.

**מה השתנה:** "נגיש" נאמר מעכשיו רק על שכבה שאימתתי בפועל, ומצוינת
השכבה במפורש — `נגיש ב-SQL` אינו `נגיש ב-API`.

**טעות 3 — סיווג בלי ציטוט ב-N-F2.** אמרתי "ההערה שגויה" בלי להדביק
את השורה. תוקן; הציטוט בסעיף הייעודי ב-`QA-FINDINGS-N.md`.

---

## 4. מה פתוח אצלי

1. **מסלול ההצלחה של `verify_phone`** — הרצת אותו בשבילי. לא אימתתי
   בעצמי ולא אטען שכן.
2. **הרתמה של המפתח אינה בריפו.** לא הרצתי אותה. הטענות שלי על N1
   הן ניתוח סטטי של הקוד החי — חזק יותר מדגימה, אבל לא ריצה.
3. **לא ראיתי מסך.** מבחן 20, בהיר/כהה וקונסולה — לא נבדקו.
4. **`address but no pin = 1`** ממתין ל-N10 של המייסד.

---

## 5. מה שמור לסבב הבא

- Q5 הוא 19 שורות עכשיו (17 + 2 WRITE-PROOF). כולן 0 פרט ל-
  `address but no pin`, שיירד ל-0 אחרי N10.
- `restore_privilege_floor` ו-`private_schema_privilege_floor` הן
  שתי מיגרציות שמתקנות את **אותה** תופעה: `drop`+`create` מחזיר ACL
  ריק. שווה שורת Q5 שסופרת פונקציות בלי ACL מפורש, כדי שהשלישית
  לא תידרש.
