# QA — ממצאי סבב N (N6)
**נכתב: 21/09/2026 · ראש מיגרציות: `20260921121155 phone_ownership_mechanism_not_yet_enforced`**
**כל ממצא כאן הורץ בהתחזות. אפס כתיבה.**

---

## N-F1 — רצפת ההרשאות של סכימת `private` פרוצה. `anon` מריץ את כל 17 הפונקציות.
**חומרה: גבוהה · סוג: פרטיות + הפרת החלטת ארכיטקטורה · מצב: פתוח**

### מה נבדק
ה-ACL של כל הפונקציות ב-`private`, ושל הסכימה עצמה, ואז הרצה בפועל
כ-`anon` בלי שום JWT.

### הראיה — הרשאות
```sql
select p.proname, coalesce(array_to_string(p.proacl,' | '),'*** DEFAULT = PUBLIC ***')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private';
```
**כל 17 הפונקציות מחזירות `*** DEFAULT = PUBLIC ***`** — אין להן ACL,
ולכן EXECUTE פתוח ל-PUBLIC. במקביל:
```
schema private nspacl = postgres=UC | authenticated=U | anon=U | service_role=U
```
ל-`anon` יש USAGE על הסכימה. USAGE + EXECUTE-ל-PUBLIC = קריאה חופשית.

### הראיה — הרצה
```sql
begin; set local role anon;
select current_user,
       private.is_operator('0de63d10-a4f8-4fac-9050-f42a6fc31898'),
       private.is_adult('0de63d10-a4f8-4fac-9050-f42a6fc31898');
rollback;
```
```
current_user = anon | is_operator = false | is_adult = true
```

### שתי הדליפות הקונקרטיות
1. **`private.is_adult(uuid)` — נגזרת של `birth_date` דולפת למשתמש לא
   מחובר.** `birth_date` נשללה ברמת עמודה **במכוון** כדי שמעסיק לא
   יקרא אותה (QA-HANDOVER §4, §6). הנגזרת שנועדה להחליף אותה נגישה
   עכשיו לכל האינטרנט, לכל uuid, בלי התחברות. הפונקציה
   `STABLE SECURITY DEFINER` ולכן עוקפת את RLS לגמרי — זו מלכודת ה׳
   בתיק החפיפה, בדיוק.
2. **`private.is_operator(uuid)` — מעמד מפעיל ניתן למניית.** ב-§5 של
   ROUND-N-POLISH נקבע מפורשות: *"טבלה ולא דגל על `profiles`, כי
   `profiles` קריא לכולם ומעמד מפעיל אינו מידע ציבורי."* הטבלה אכן
   חסומה — אימתתי, ראה N-P2 — אבל הפונקציה שקוראת אותה לא. ההחלטה
   הארכיטקטונית מנוטרלת על ידי ברירת מחדל של Postgres.

### מה היה אמור לקרות
`anon` אמור לקבל `permission denied for function`, כפי שהוא מקבל על
`verify_phone` (שם יש ACL מפורש ולכן זה עובד).

### התיקון — מה שהצעתי היה שגוי, ומה שהוחל
**הצעתי:**
```sql
revoke execute on all functions in schema private from public, anon, authenticated;
```
**זה היה מסוכן, וה-Tech Lead צדק לפסול.** אחת-עשרה מדיניות RLS קוראות
לפונקציות האלה, ומדיניות מוערכת **בתור התפקיד השואל** — לא בתור בעל
הפונקציה. הסרה גורפת מ-`authenticated` הייתה מחזירה
`permission denied` על חמש טבלאות.

**הטעות שלי מדויקת וכדאי שתירשם:** בדקתי שאף פונקציית `SECURITY INVOKER`
אינה קוראת ל-`private.` — וזה נכון — והסקתי מזה "בטוח". **לא בדקתי
`pg_policies`.** מדיניות היא מסלול קריאה שלישי, לא פונקציה ולא טריגר,
והיא זו שנשברת. בדיקת `pg_proc` לבדה אינה מכסה את שטח הקריאה.

**מה שהוחל בפועל** (`20260921125841 private_schema_privilege_floor`):
רצפה לפי פונקציה ולא לפי סכימה. אימתתי אחרי ההחלה:

| פונקציה | ACL אחרי | מדיניות שמשתמשות |
|---|---|---|
| `is_business_member` | `postgres=X \| authenticated=X` | 7 |
| `counterpart_submitted` | `postgres=X \| authenticated=X` | 2 |
| `is_business_owner` | `postgres=X \| authenticated=X` | 2 |
| `shift_business` | `postgres=X \| authenticated=X` | 2 |
| `is_adult` · `is_operator` · `may_manage_shift` · `point_near_city` | `postgres=X` בלבד | 0 |

`anon` הוסר מכל 17.

### דיוק החומרה — תיקון שלי
כתבתי "דליפת פרטיות פעילה... פתוחה לכל האינטרנט". **זו הייתה קפיצה
שלא הוכחתי.** ה-API של PostgREST חושף את סכימת `public` בלבד; לא הייתה
דרך להגיע ל-`private.is_adult` מבחוץ. הראיתי הרשאה שגויה ברמת SQL,
והצגתי אותה כניצולת מרחוק. **החומרה הנכונה: בינונית — רצפת הרשאות
שגויה והפרת החלטת ארכיטקטורה, לא דליפה פעילה.**

### אימות אחרי התיקון — הרצתי, לא הנחתי
```sql
begin; set local role anon;
select private.is_adult('0de63d10-…'); rollback;
-- ERROR 42501: permission denied for schema private

begin; select set_config('request.jwt.claims','{"sub":"0de63d10-…","role":"authenticated"}',true);
set local role authenticated;
select private.is_adult('136a89c4-…'); rollback;
-- ERROR 42501: permission denied for function is_adult
```
**וחמש הטבלאות לא נשברו** — קריאה מלאה בשתי זהויות, בלי permission denied:

| זהות | profiles | contacts | businesses | members | shifts | applications | reviews | team |
|---|---|---|---|---|---|---|---|---|
| `E_OWNER` (ביסטרו נוטר) | 10 | 2 | 2 | 1 | 3 | 1 | 0 | 0 |
| `W_OTHER` | 10 | 1 | 2 | 0 | 3 | 0 | 0 | 0 |

`W_OTHER` רואה רק את שורת הקשר שלו ואפס מועמדויות — המטריצה של Q2
כפי שהיא אמורה להיראות.

## N-F2 — `phone_conflict` הוא קוד מת, וההערה שמסבירה אותו שגויה
**חומרה: נמוכה · סוג: הנמקה שגויה בקוד · מצב: פתוח**

### מה נבדק
הענף ב-`verify_phone` מול האינדקסים בפועל על `profile_contacts`.

### הראיה
```sql
select indexdef from pg_indexes
where schemaname='public' and tablename='profile_contacts' and indexdef ilike '%phone%';
```
```
CREATE UNIQUE INDEX profile_contacts_phone_key
  ON public.profile_contacts USING btree (phone) WHERE (phone IS NOT NULL);
```
ולכן `select count(*) ... where phone = v_phone and id <> p_user` לא
יכול לחרוג מ-0 לעולם. הענף אינו ניתן להגעה. בפועל: 0 טלפונים כפולים.

### הבעיה האמיתית אינה הקוד המת
ההערה בגוף הפונקציה אומרת:
> *"Uniqueness lives in Supabase Auth today, so a duplicate should be impossible."*

**זה לא נכון.** הייחודיות נאכפת באינדקס הזה, במסד, במרחק שורה אחת
מההערה. מפתח עתידי שיקרא את ההערה עלול להסיר את האינדקס בהנחה
ש-Auth מכסה — ואז גם האכיפה וגם ההגנה בעומק נעלמות יחד.

### הציטוט המדויק, כפי שביקשת
נמשך מ-`pg_get_functiondef`, שורות 16–20 בגוף הפונקציה:
```
16:   -- Uniqueness lives in Supabase Auth today, so a duplicate should be
17:   -- impossible. If one ever exists, refuse rather than verify the wrong person.
18:   select count(*) into v_other from public.profile_contacts
19:    where phone = v_phone and id <> p_user;
20:   if v_other > 0 then return jsonb_build_object('result','phone_conflict','others',v_other); end if;
```
**המשפט הלא מדויק הוא שורה 16:** `"Uniqueness lives in Supabase Auth today"`.

הייחודיות נאכפת שתי שורות משם, במסד:
```
CREATE UNIQUE INDEX profile_contacts_phone_key
  ON public.profile_contacts USING btree (phone) WHERE (phone IS NOT NULL);
```

### התיקון המוצע
להשאיר את הענף (הגנה בעומק לגיטימית) ולתקן את ההערה כך שתנקוב
בשם האינדקס `profile_contacts_phone_key` כמקור האכיפה.

### מה לא הוכחתי
כדי להריץ את הענף בפועל צריך להפיל את האינדקס ולהזריק כפילות — DDL
וכתיבה. לא רלוונטי לדעתי; הראיה המבנית מספיקה.

---

## N-Q1 — נענה: בכוונה. סגור.
**הכרעת Tech Lead (START-HERE, 21/09):** הלוח דורש התחברות בכוונה,
ומעולם לא היה מסלול עובד ל-`anon` — כל המדיניות היא `to authenticated`,
ולכן `anon` קיבל אפס שורות גם כשה-EXECUTE היה בידיו. **§4 ב-
`QA-HANDOVER.md` עודכן.** לא לדווח שוב.

## מה עבר, עם ראיה

### N-P1 — `verify_phone` / `unverify_phone`: לא־מפעיל מסורב
```sql
begin;
select set_config('request.jwt.claims','{"sub":"0de63d10-...","role":"authenticated"}', true);
set local role authenticated;
select current_user, auth.uid(), (select count(*) from profile_contacts), private.is_operator();
select public.verify_phone('136a89c4-...');                          -- יעד תקין
select public.verify_phone('00000000-0000-0000-0000-000000000000');  -- משתמש לא קיים
select public.verify_phone('ffffffff-0000-0000-0000-00000000000b');  -- משתמש בלי טלפון
select public.unverify_phone('136a89c4-...');
rollback;
```
```
current_user = authenticated · auth.uid() נכון · contacts visible = 1 (שלו בלבד)
is_operator = false
כל ארבע הקריאות → {"result": "forbidden"}
```
**ובנוסף, נקודה לזכותך:** שער המפעיל קודם לפתרון היעד. לכן לא־מפעיל
מקבל `forbidden` זהה גם על uuid קיים, גם על לא קיים, וגם על אחד בלי
טלפון. **אין מניית משתמשים דרך `verify_phone`.** זה לא מקרי בקוד וזה
שווה שמירה.

### N-P2 — `private.operators` אינו נגיש
```sql
begin; set local role anon;         select count(*) from private.operators; rollback;
-- ERROR 42501: permission denied for table operators
begin; set local role authenticated; select count(*) from private.operators; rollback;
-- ERROR 42501: permission denied for table operators
```
`relacl = postgres=arwdDxtm/postgres` — אין מענק לאף תפקיד. הטבלה
ריקה (0 שורות), כמתועד.

### N-P3 — `anon` אינו יכול לקרוא ל-`verify_phone`
```
ERROR 42501: permission denied for function verify_phone
```
`proacl = postgres=X | authenticated=X | service_role=X`. תקין.

### N-P4 — Q5 בפתיחה ובסגירה
17 שורות + 2 שורות WRITE-PROOF. **זהות בפתיחה ובסגירה.** כולן 0,
פרט ל-`address but no pin = 1` (ביסטרו נוטר, ממתין ל-N10 של המייסד).
`phone_verified` נשאר 0 ו-`private.operators` נשאר 0 — הוכחה שלא
כתבתי כלום.

---

## N-P5 — N1: הקיבוץ אינו מאבד שורות. הוכחה מבנית, לא דגימה.
**נבדק על `app.html` 141,069 בתים, 21/09 16:55** (אחרי מסירת הביניים
של המפתח ב-15:56 — הקובץ השתנה מאז, ולכן בדקתי את מה שחי).

### הטענה: סכום השורות בכל הדליים == `boardShifts()`
```js
const bucketOf = d => { const n = dayOffset(d); return n <= 0 ? 0 : n === 1 ? 1 : n <= 6 ? 2 : 3; };

function boardBuckets(){
  const g = [[],[],[],[]];
  for(const s of boardShifts()) g[bucketOf(new Date(s.starts_at))].push(s);
  return g;
}
```
`bucketOf` היא שרשרת טרנארית **טוטאלית**: כל מספר ממשי נופל לאחד
מ-{0,1,2,3} בדיוק. `boardBuckets` דוחפת כל איבר של `boardShifts()`
פעם אחת. `boardListC` מרנדרת כל איבר בכל רשימה לא ריקה
(`if(!list.length) return;` מדלגת על דלי ריק, לא על שורה).
**לכן הסכום שווה בזהות, לא רק בדגימה.**

**כולל המקרה שהורג קיבוצים:** `starts_at` לא תקין → `new Date(…)`
→ `Invalid Date` → `dayOffset` מחזיר `NaN`. `NaN <= 0` שקר,
`NaN === 1` שקר, `NaN <= 6` שקר → נופל ל-`3`. המשמרת מגיעה ל"בהמשך"
במקום להיעלם או להפיל את `g[undefined].push`. זה שורד במקרה, לא
בתכנון — אבל זה שורד.

**המפתח דיווח `3 == 3` על שלוש משמרות.** הדיווח נכון ועקבי; הוא פשוט
מוכיח הרבה פחות ממה שהמבנה מוכיח. אין לי הסתייגות מהמסירה.

### הטענה: `.c-act` רק בדלי "היום"
```js
const bucketActs = i === 0;     // דלי "היום" בלבד
…
${bucketActs && canClaim ? claimBtn(s, 'c-act') : ''}
```
שני אתרי קריאה בלבד ל-`claimBtn` בקובץ כולו:
- `app.html:1291` — `claimBtn(s, 'c-act')`, תחת `bucketActs && canClaim`
- `app.html:1424` — `claimBtn(s)` בפופאפ המפה, **בלי** המחלקה

אין אתר שלישי, ו-`shiftCard` הישן נמחק לגמרי (0 מופעים). לכן `.c-act`
אינו ניתן לפליטה מחוץ ל-`i === 0`.

`.has-act` יושב על **כל** שורה בדלי 0, גם על שורה עם `canClaim === false`
(משמרת מלאה) — תואם את ההכרעה ב-START-HERE ומונע את קפיצת 164px.

### מה לא בדקתי, ולמה
**לא הרצתי את הרתמה.** המפתח כתב שהיא ב-scratchpad ולא בריפו; מה
שיושב בתיקייה הוא `N2-HARNESS-CACT.html` של המעצב, והוא **לא** מכיל
את שתי הטענות: הוא מקודד `bucket` ידנית בכל שורת נתונים, לא קורא
ל-`bucketOf` האמיתית, ועדיין משתמש ב-`ui.bucket_weekend` שהוחלף
ב-`ui.bucket_thisweek`. **זו הערה על מה שנגיש לי, לא טענה שהמפתח לא
הריץ.** אם אתה רוצה שהטענות יישמרו בין סבבים — הן צריכות להיות בריפו.

**לא ראיתי את המסך.** כל האמור לעיל הוא ניתוח סטטי של הקוד החי.
מבחן 20, מצב בהיר/כהה, וקונסולה נקייה — לא בתחומי בסבב הזה.
