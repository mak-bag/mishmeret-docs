# DEV BRIEF Q2 — כרטיס משמרת · לוחות · תפקיד חופשי
**Tech Lead · 25/09/2026 · השרת מוכן ונבדק בהתחזות. נשאר לקוח בלבד.**

```
--- מצב כל המחלקות, 25/09/2026 ---
מסד:    3 מיגרציות חדשות (ראש: shift_details_hint_array_fix) · מבחן שלמות 15/15
קוד:    app.html 162,874 · המחזיק: Developer · לא בקומיט
QA:     base/board שקרית על וקטור — בריף ב-TECHLEAD-Q1-MAP-VERDICT.md
מייסד:  אישר את שלושת הפיצ'רים. בלי סכומי כסף בלוח העובד.
--- סוף מצב ---
```

## 0. כלל כסף (המייסד, 25/09)
**סכומים מופיעים על המפה, בלוח ובכרטיס. אף פעם לא בלוחות — לא של העובד ולא של המגייס.**
השרת כבר לא מחזיר `rate` ל־`biz_dashboard`.

## 1. כרטיס משמרת לפני הגשה
לחיצה על שורה בלוח או על משמרת בפופאפ של המפה פותחת כרטיס. ההגשה נעשית מתוך הכרטיס.

```
rpc('shift_details', { p_shift }) → { result:'ok', role_code, role_label, biz_name, city,
  address|null, lat, lng, located:bool, distance_km|null, transit_hints:['night'|'shabbat'],
  transport, starts_at, ends_at, timezone, rate, currency, descr, urgent, adults_only, ... }
```
- **מרחק:** `ui.details_distance` עם `{n}` = `distance_km`. אם הערך `null` (אין עיר) — לא מציגים את השורה.
- **Waze:**
  - אם `located` → `https://waze.com/ul?ll=${lat},${lng}&navigate=yes`
  - אחרת, אם יש כתובת → `https://waze.com/ul?q=${encodeURIComponent(address+', '+city)}&navigate=yes`
  - אחרת → בלי כפתור, ובמקומו `ui.details_no_pin`.
  - **לעולם לא לנווט לקואורדינטה שהיא מרכז העיר.**
- **תחבורה ציבורית:** כפתור `ui.details_transit` שפותח את Google Maps. לא משתמשים ב־API, ולכן אין עלות:
  `https://www.google.com/maps/dir/?api=1&destination=<אותו יעד כמו ב-Waze>&travelmode=transit`
  מתחתיו, לכל רמז: `ui.transit_night`, `ui.transit_shabbat`. אם `transport` → `ui.details_transport`.
- הכרטיס לא טוען נתונים מראש. קריאה אחת בכל פתיחה.

## 2. לוח העסק (לשונית חדשה בצד המגייס)
```
rpc('biz_dashboard', { p_business }) → { result, live:[{shift_id, role_code, role_label,
  starts_at, ends_at, slots, filled, applied, offered, in_range}],
  team:[{worker_id, full_name, shifts_done, last_at, attended_yes, attended_no, phone, note, is_regular}] }
```
- **משמרות פעילות:** לכל משמרת `ui.dash_in_range` עם `{n}`.
  **כש־`in_range=0` מציגים `ui.dash_in_range_zero` בסגנון אזהרה.** זה הערך העיקרי של הלוח: המעסיק יודע שאף אחד לא רואה את המשמרת.
- **עבדו אצלך:** שם, `plural('ui.dash_shifts_done', n)`, תאריך אחרון, טלפון (מותר לחשוף — הם שובצו), הגיע ולא הגיע, והערה.
  - ריק → `ui.dash_team_empty`.
- **הערה פרטית:** שדה טקסט (עד 500 תווים) ומתחתיו `ui.dash_note_hint`.
  - שמירה: `rpc('set_private_note', {p_business, p_worker, p_note})`.
  - טקסט ריק מוחק את ההערה.
- **סימון הגעה:** במסך המשמרת של המעסיק, בשורה של עובד `confirmed`, אחרי שהמשמרת התחילה, שני כפתורים: `ui.dash_attended` ו־`ui.dash_no_show`.
  `rpc('mark_attendance', {p_shift, p_worker, p_attended:'yes'|'no'})`

## 3. לוח העובד ("העבודות שלי")
```
rpc('worker_dashboard') → { result, shifts_done, upcoming,
  businesses:[{business_id, name, city, phone, shifts_done, last_at, note}] }
```
- כותרת: `plural('ui.dash_shifts_done', shifts_done)` ו־`ui.dash_upcoming`.
- **בלי סכומי כסף. זו החלטת המייסד.**
- לכל עסק: שם, עיר, מספר משמרות, תאריך אחרון, והערה פרטית (אותה פונקציה, עם `p_worker` = המשתמש עצמו).
- ריק → `ui.dash_businesses_empty`.

## 4. תפקיד "אחר" עם מלל חופשי
- `terms` כולל עכשיו את `role/other` ("אחר"). כשבוחרים בו בטופס הפרסום או העריכה, מופיע שדה `ui.role_label` (עד 40 תווים).
- `post_shift` ו־`edit_shift` מקבלים את הפרמטר `p_role_label`. תפקיד אחר בלי שם → `result.bad_role_label`.
- **בכל מקום שמציגים תפקיד** (לוח, מפה, כרטיס, המשמרות שלי, צד המעסיק), משתמשים בפונקציה אחת:
  `roleName(s) = s.role_label || term('role', s.role_code)`

## 5. כל המחרוזות כבר זרועות (he+en)
הרשימה המלאה נמצאת ב־`terms` תחת הקידומות `ui.details_*`, `ui.transit_*`, `ui.dash_*`, `ui.role_label` ו־`result.*` החדשות.
**אין לכתוב עברית בקוד.** אם חסרה מחרוזת, בקשו ממני.

## 6. עוד בקשה
לנעול את גרסת ספריית המפה בשתי השורות האלה:
```
app.html:1236–1237   maplibre-gl@5  →  maplibre-gl@5.24.0
```

```
--- HANDOFF TO: Developer ---
DONE:      5 RPC חדשות + p_role_label. כולן נבדקו בהתחזות ב-rollback:
           הרשאות (זר → forbidden, בלי קשר → no_relationship),
           בלי תווית → bad_role_label, תווית בתפקיד רגיל נמחקת,
           ו-in_range מחושב. ל-anon אין גישה לאף פונקציה.
STATE:     אין שינוי בלקוח. shifts_for_me מחזירה עכשיו גם role_label.
NEXT:      §1 כרטיס → §4 roleName → §2 לוח עסק → §3 לוח עובד.
MUST KNOW: private_notes נגישה רק דרך RPC. SELECT ישיר נכשל בכוונה.
           QA חייב להוסיף את 5 ה-RPC ל-fake-sb.js (מלכודת 7), אחרת הרתמה תאדים.
OPEN:      —
--- END HANDOFF ---
```
