# DEV → TECH LEAD · S§6 סעיף 7 — תור המפעיל

**Developer · 06/10/2026 · `app.html` 265,527 · md5 `47BC3F125EA7` · ללא BOM**
**נשמר: `builds/app-47BC3F125EA7.html`**

**למה זה הפריט הזה:** מימוש מסירה A חסום על אישור המייסד (`DESIGN-V1-A`
נמסר ב-05/10 23:07, אין מסמך אישור). סעיף 7 אינו חסום על אף אחד,
ולכן הוא הבא בתור.

## מה נכנס

- **`loadOpQueue()`** — `pending_verifications()` **רק כש-`is_operator`**.
  למשתמש רגיל אין כאן קריאה נוספת בכלל. **נמדד: `opCalls: 0`** בריצת
  הרתמה (פרופיל רגיל).
- **`opQueueBox()`** בחשבון, באותו מסך ובלי שלב נוסף: שם, עיר, ח.פ.,
  והקישור לראיה — **נפתח בלשונית חדשה** (`target="_blank" rel="noopener"`).
- **שני כפתורים לכל שורה:** `ui.op_approve` / `ui.op_reject` →
  `verify_business({p_business, p_approve})` → `resultText` → טעינת
  התור מחדש. **נגיעה אחת.**
- ריק → `ui.op_empty`.

**אימתתי את החוזים מול `pg_proc` לפני הכתיבה:**
`pending_verifications() -> jsonb` עם `{result, items[]}`, ו-
`verify_business(p_business uuid, p_approve boolean) -> jsonb`.

**ולא הוספתי סינון שני:** השרת כבר מוציא מהתור עסק שהמפעיל חבר בו
(`not private.is_business_member(b.id)` — הממצא של QA, S-1). סינון
נוסף בלקוח היה יכול לסטות ממנו. אם בכל זאת יחזור `own_business` —
הוא מוצג כ-`resultText` ולא נבלע.

## מה אומת

- **רתמה `fx=worker` — 19/23**, ארבע האדומות המוכרות
  (`base/board` · `S-stars-3` · `S-vr-l2` · `T-hours`).
- **אפס שגיאות קונסולה · CSP `MATCH ... no BOM`.**
- **`pending_verifications` לא נקראה** לפרופיל שאינו מפעיל.

## ‼ מה לא אומת — ולמה

**ממשק המפעיל עצמו לא רץ באף ריצה.** ב-`RPC.my_profile` של הרתמה אין
`is_operator:true`, ולכן `opQueueBox()` מחזיר מחרוזת ריקה בכל
הפיקסצ׳רים. **הקוד נקרא ולא רץ, ואני לא כותב "עבר".**

**מה שצריך (QA):** פיקסצ׳ר `?fx=operator` — `my_profile` עם
`is_operator:true` ו-`pending_verifications` שמחזירה שתי שורות.
ואז שתי טענות: התור מוצג למפעיל בלבד, ולחיצה על אישור שולחת
`verify_business` עם `p_approve:true`.

זהו הפער השלישי מאותו סוג השבוע (`offered` ב-MINE, המסך של
`S-stars-3`, וכאן) — **כל אחד מהם הוא יכולת שנכתבה ואין פיקסצ׳ר
שנוגע בה.**

```
--- HANDOFF TO: Tech Lead ---
DONE:      §6.7 תור המפעיל: טעינה רק ל-is_operator, תיבה בחשבון עם
           שם/עיר/ח.פ./קישור, אישור ודחייה בנגיעה אחת, וטעינה מחדש.
           החוזים אומתו מול pg_proc. רתמה 19/23, אפס שגיאות קונסולה,
           CSP MATCH ללא BOM. נמדד: אפס קריאות למשתמש רגיל.
STATE:     app.html 265,527 · 47BC3F125EA7 · נשמר ב-builds/.
NEXT:      מסירה A ברגע שהמייסד מאשר. בינתיים §6.8 (תמונות) אם תרצה.
FOR YOU:   שלושה פיקסצ׳רים חסרים חוסמים אימות של שלוש יכולות:
           MINE עם offered · מסך הבית ב-S-stars-3/S-vr-l2 · fx=operator.
MUST KNOW: לא הוספתי סינון own_business בלקוח — השרת כבר עושה זאת,
           ושתי גרסאות לאותו כלל הן בדיוק מה שנשבר בעבר.
OPEN:      Heebo מקומי — דורש הורדת קבצי woff2. לא הורדתי בלי אישור.
--- END HANDOFF ---
```
