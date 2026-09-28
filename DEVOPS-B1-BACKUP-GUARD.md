# DevOps · B1 — השמירה ל-`backup.yml`, בדוקה ומוכנה להחלה
**28/09/2026 · מאושר ב-`ROUND-S` §8 · נחסם אצלי, מועבר להחלה ידנית**

## מה זה עושה
דוחה מראש `SUPABASE_DB_URL` שמשתמש ב-`postgres` בלי סיומת הפרויקט,
**הכשל שהפיל שבע ריצות לילה ברצף.** במקום `FATAL: password
authentication failed` — הודעה שאומרת מה בדיוק לתקן, בשנייה הראשונה.

## איפה
`.github/workflows/backup.yml`, בתוך הצעד `Dump`:
**אחרי** ה-`fi` של שומר ה-IPv6, **לפני** השורה `echo "STAMP=..."`
(שורה 77 בקובץ הנוכחי). הוספה בלבד — שום שורה קיימת לא משתנה.

```bash
          # הפולר מנתב לפרויקט לפי שם המשתמש, ולכן הוא חייב להיות
          # postgres.<project-ref>. עם postgres בלבד ההזדהות נופלת על
          # "password authentication failed" — הודעה מטעה, כי הסיסמה
          # עשויה להיות תקינה לגמרי. שבע ריצות לילה נשרפו על זה (27/09).
          # ה-ref אינו סוד: הוא מופיע בכתובת ה-API שהדפדפן קורא ממילא.
          if echo "$DB_URL" | grep -q 'pooler\.supabase\.com' \
             && echo "$DB_URL" | grep -qE '://postgres[:@]'; then
            echo "SUPABASE_DB_URL uses the bare user 'postgres'." >&2
            echo "The session pooler routes by username, so it needs the ref:" >&2
            echo "  postgres.rkmjggormlxcvzuqedig" >&2
            echo "Copy the Session pooler URI from Dashboard > Connect." >&2
            exit 1
          fi
```

**הקובץ המלא והמוכן:** `docs/backup.yml.proposed` (9,754 בתים; המקור
8,796). הפרש: הוספה אחת רצופה, 13 שורות. אימתתי ב-`diff`.

## נבדק — חמישה מקרים, כולל השבור
```
bare postgres on pooler   -> REJECT(bare-user)   ← הכשל האמיתי של 7 הלילות
correct postgres.<ref>    -> PASS
direct IPv6 host          -> REJECT(ipv6-direct) ← השומר הישן, לא נדרס
bare postgres, no pw      -> REJECT(bare-user)
pw containing 'postgres:' -> PASS                ← אין התראת שווא
```
הרצתי את שני השומרים יחד על חמש המחרוזות. **השמירה נופלת על הקלט
השבור ועוברת על התקין** — לפי הכלל ש-`PRODUCTION-CONTROL` §5.5 קובע.

## למה לא דחפתי
סיווג ההרשאות של הסביבה חוסם כתיבה לריפו הפרודקשן (`Production
Deploy`), בלי קשר לאישור ב-§8. **לא עקפתי ולא אעקוף.** ההחלה היא
פעולה שלך או של המייסד.

## סדר ההפעלה — שני דברים, ורק אז יש גיבוי
1. **המייסד** מתקן את `SUPABASE_DB_URL`:
   Dashboard → Connect → **Session pooler** (לא Direct connection),
   ומחליף `[YOUR-PASSWORD]` בסיסמה. השם חייב להיות
   `postgres.rkmjggormlxcvzuqedig`.
2. **מישהו לוחץ** `Run workflow` על `main`.

השמירה הזו אינה תנאי לשום אחד מהשניים — היא מוודאת שהלילה השמיני
לא יהיה שקט כמו שבעת הקודמים.

## מה לקרוא בריצה הירוקה הראשונה
1. `Drill assertions` — `head` חייב להיות **`20260927190409`**
   (ראש המיגרציות הנוכחי, 61 מיגרציות). אם לא — הדאמפ אינו של המסד הזה.
2. **סכימת `auth`** — התרגיל משחזר רק `public` ו-`supabase_migrations`.
   הוא אינו מוכיח ש-`auth` בדאמפ, ובלעדיה שחזור מחזיר כל נתון ואיש
   לא מתחבר. **השאלה הראשונה על הדאמפ הראשון.**
3. `TABLES -ge 12` ו-`NONZERO -ge 6` — המסד כבר גדול מספיק (12
   משתמשים, 5 עסקים, 11 משמרות, 8 מועמדויות), אז אלה אמורות לעבור.
   אם ייפול — הטענה שגויה, לא הגיבוי.
