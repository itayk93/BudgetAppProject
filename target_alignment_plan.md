# תכנון יישום התאמה בין BudgetApp ל־budget_app_project

## 1. מה למדנו מהפרויקט האינטרנטי (`budget_app_project`)
- `BUDGET_FLOW_DOCUMENTATION.md` מסביר שהיעד החודשי/הצפי נטען מטבלת `category_order` (עמודות `monthly_target`, `use_shared_target`, `shared_category`) והעסקאות מחולקות לפי חודש/שבוע כשה־`progress bar` פשוט בונה את היחס `spent / effective_target`. המסך מעודכן באמצעות `api/dashboard` שמחזיר את `category_breakdown` עם כל השדות האלה.
- `client/src/components/Modals/MonthlyTargetModal.js` מראה איך העדכון מתבצע: טופס עם שדה סכום, כפתור לקבלת הצעה (`calculateMonthlyTarget`) וגם תמיכה ביעד משותף (`calculateSharedTargets` + `getSharedTarget`). אחרי החישוב המטרה נשמרת אוטומטית ושולחת `onTargetUpdated` כדי שה־`CategoryCard` יעדכן את ה־progress bar.
- `client/src/components/CategoryCard/CategoryCard.js` מציג גבול בקטגוריה (או קבוצה משותפת) עם פס התקדמות של `currentTarget` והודעות של „נשאר להוציא״ / „חריגה״, ונותן חלוקה שבועית אם `weekly_display = true`. כך משפיע העדכון במודאל על הפרוגרס בעמודת התזרים.

## 2. מצב קיים ב־BudgetApp
- `CashflowCardsView.swift` מציג `CategorySummaryCard` לכל קטגוריה, ומציג כפתור `EditTargetView` דרך `selectedCategoryForEdit`. הנתונים שכותבי `CategorySummary` (קו 41 ב־ViewModel) מחושבים מתוך עסקאות ו־`categoryOrderMap`, אבל `updateTarget(for:)` רק מעדכן את המפה הפנימית – אין קריאה לשרת.
- `CategorySummaryCard` (באותו קובץ סביב שורה 2098) משתמש ב־`ProgressCapsule` ומריץ `statusBadge` עם היחס `category.totalSpent / target`. `weeklyDisplay` גם משתמש בנתונים של `weekly` ו־`weeklyExpected` כדי להראות שבועות.
- `EditTargetView.swift` הוא המסך בו מזינים את היעד, אבל הוא לא מכיל RTL ולך אין אחיזת ציוד כמו הצעה אוטומטית או הודעת שמירה.
- `CashFlowDashboardViewModel.swift` מייצר את `CategorySummary` מתוך העסקאות, חושב הצעה פשוטה (3 חודשי עבר) והעדכון אינו מתבסס על נתוני shared target מהשרת.

## 3. פערים מרכזיים שיש לסגור
1. עדכון היעד אינו מתבצע מול ה־API (`categories/update-monthly-target`), ולכן אין סנכרון עם `monthly_target` ב־`category_order` וה־progress ידני.
2. אין תמיכה חכמה במטרות משותפות (shared categories) או ביעדים המחשבים על ידי ה־`MonthlyTargetModal` שהפרויקט האחר מציג.
3. המסך לעריכת היעד לא מיושר לימין, ולכן חוויית RTL אינה אחידה.
4. ה־ViewModel אינו מקבל (למשל מ־`DashboardData`) את השדות `shared_category`, `weekly_display`, `monthly_target` שה־API מספק, ולכן המצב חורג מהלוגיקה של `budget_app_project`.

## 4. צעדים מפורטים ליישום
1. **שדרוג שכבת הנתונים ליעדים:**
   - להשתמש ב־`Services/CategoriesTargetsService.swift` כדי לקרוא ל־`calculateMonthlyTarget`, `updateMonthlyTarget` ו־`calculateSharedTargets` כפי שמודגם ב־`MonthlyTargetModal.js`.
   - ב־`CashFlowDashboardViewModel` יש לעדכן את `updateTarget(for:)` / `suggestTarget(for:)` לבצע קריאות רשת ולא רק ללוקאל, ועד אחרי שימור להפעיל `refreshData()`.
   - לשמור חזרה את תוצאת החישוב ב־`categoryOrderMap` כדי ש־`buildCardsForCurrentMonth` יקבל את `monthlyTarget` החדש.

2. **הרחבת המודל כדי לתמוך ביעדים משותפים:**
   - להוסיף ל־`CategorySummary` שדות כמו `sharedCategory`, `useSharedTarget`, `effectiveTargetSource` וכדי לאגד את היעד המשותף (בדומה ל־`sharedTarget` ב־`CategoryCard.js`).
   - ב־`buildCardsForCurrentMonth` לשאוב את `shared_category` ו־`use_shared_target` מ־`categoryOrderMap` ולכן לחבר את סכום הוצאות הקטגוריה עם היעד המשותף לפני החישוב של פס התקדמות.
   - לוודא ש־`GroupSectionCard` מסכם את היעד המשותף (נבדק סביב שורות 1330–1400 ב־`CategoryCard.js`).

3. **סינכרון התצוגה עם היעד המשותף:**
   - `CashflowCardsView.swift` (שורות 384 לערך) צריך להעביר לחיתול `CategorySummaryCard` גם את היעד המשותף כדי שה־progressRatio יתבסס על מה שמשתמש עדכן.
   - להוסיף בלוחות `CategorySummaryCard` (באותו קובץ) טקסט שמציג „נשאר להוציא״/„חריגה״ מדויק לפי הפער, וכן הודעה על יעד מוצע אם `isTargetSuggested`.

4. **שדרוג מסך עריכת היעד:**
   - להעשיר את `EditTargetView.swift` או להחליף אותו בגרסה דומה ל־`MonthlyTargetModal`: להציג טקסטר עם סמל ₪, קישור להצעה חכמה (הפעלת `vm.suggestTarget`), הודעות שגיאה/הצלחה ולעדכן את הערך ב־`target`.
   - לאפשר שמירת ערך חדש דרך `onSave` ולהפעיל `Task` שמבצע קריאה ל־API (`CategoriesTargetsService`).
   - להוסיף `@Environment(\.layoutDirection)` או פשוט להקיף את `.sheet` ב־`CashflowCardsView` עם `.environment(\.layoutDirection, .rightToLeft)` כדי להשיג את מסך ה־RTL שמבוקש.

5. **חוויית פרוגרס בטופס:**
   - לוודא שה־`ProgressCapsule` (bimonth detail around lines 2111–2168) מועילה לכל שינוי ערך היעד, כך שה־`progressRatio` מעודכן באופן דינמי בפייסבוק.
   - לבצע בדיקות ידניות/קצרות כדי לבדוק שבכל עדכון יעד (גם shared) הפס מתעדכן ונשאר/חריגה מחושבים נכון.

6. **בדיקות, שיפור ונראות:**
   - להריץ את המסך ולוודא ששינוי יעד משפיע על כרטיס הקטגוריה, ושהפרוגרס משקף בדיוק את היחס בין `totalSpent` ל־`target`.
   - לבדוק את המסך החדש במצב RTL (כל השדות מימין לשמאל).
   - לוודא שאין שינויים במצב הקיים (transaction editing, weekly grid) שנשמרים בגלל העדכון.

## 5. מסמכי תמיכה למימוש
- `budget_app_project/BUDGET_FLOW_DOCUMENTATION.md` – מציין את היעדים השבועיים/חודשיים, `shared_category` ו־progress bar.
- `budget_app_project/client/src/components/Modals/MonthlyTargetModal.js` – מראה את טופס העריכה, הצעות חישוב, שמירה אוטומטית ו־API הרלוונטיים.
- `BudgetApp/Views/CashflowCardsView.swift` ו־`BudgetApp/Views/EditTargetView.swift` – נקודות ההחדרה של המסך, כרטיסי הקטגוריות וה־sheet.
- `BudgetApp/ViewModels/CashFlowDashboardViewModel.swift` – שם נממש את קריאות ה־API לעדכון/חישוב, נשמור את המפה, ונעדכן את מסך הכרטיסים.
- `BudgetApp/Services/CategoriesTargetsService.swift` – כבר קיים וניתן להרחיב אותו כדי לתמוך בהתאמות נוספות מהשרת.
