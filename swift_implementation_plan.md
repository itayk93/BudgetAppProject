# תוכנית הטמעה מפורטת: הצגת יעדים חודשיים (SwiftUI)

## הקדמה
תוכנית זו מפרטת את השלבים הנדרשים להטמעת תצוגת יעד הוצאה/הכנסה חודשי באפליקציית ה-Swift, בהתבסס על ניתוח הקוד הקיים. התהליך מחולק לשלוש שכבות: מודל, ViewModel, ו-View.

---

## חלק 1: שכבת המודל (Model)

הבסיס לכל התהליך הוא המודלים שמייצגים את הנתונים שלנו.

### 1.1. מודל `CategoryOrder.swift`
- **מטרה**: לייצג את המידע המתקבל מה-API עבור הגדרות קטגוריה.
- **שדה מרכזי**:
  ```swift
  let monthlyTarget: String?
  ```
- **הסבר**: המאפיין `monthlyTarget` מוגדר כ-`String` אופציונלי, כדי להתאים לסוג הנתונים בבסיס הנתונים. ה-ViewModel יהיה אחראי להמיר אותו למספר.

### 1.2. מודל `CategorySummary` (בתוך ה-ViewModel)
- **מטרה**: להוות "חבילת מידע" מוכנה עבור התצוגה, המכילה גם את נתוני היעד וגם את נתוני ההוצאות.
- **שדות מרכזיים**:
  ```swift
  struct CategorySummary {
      let name: String
      let target: Double? // <-- היעד לאחר המרה
      let totalSpent: Double // <-- סך ההוצאות שחושב
      // ... שדות נוספים
  }
  ```
- **הסבר**: ה-ViewModel יוצר את המודל הזה כדי לפשט את הלוגיקה בשכבת התצוגה.

---

## חלק 2: שכבת הלוגיקה (ViewModel)

`CashFlowDashboardViewModel.swift` הוא המוח של התהליך. הוא מאחזר, מעבד ומכין את הנתונים עבור התצוגה.

### 2.1. אחזור נתונים
- ה-ViewModel משתמש ב-`CategoryOrderService` כדי לקבל את רשימת הגדרות הקטגוריות מה-API.
- התוצאות נשמרות במילון בשם `categoryOrderMap`, המאפשר גישה מהירה להגדרות של כל קטגוריה לפי שם.

### 2.2. עיבוד והכנת הנתונים
- **הפונקציה המרכזית**: `_buildAllExpenseCategorySummaries()`
- **תהליך**:
    1. הפונקציה עוברת על כל העסקאות של החודש הנוכחי ומקבצת אותן לפי שם קטגוריה.
    2. עבור כל קטגוריה, היא ניגשת ל-`categoryOrderMap` כדי למצוא את הגדרותיה.
    3. **השלב הקריטי - שליפת היעד**: בשלב זה, היא שולפת את היעד מהמפה וממירה אותו למספר מסוג `Double`.
       ```swift
       // מתוך _buildAllExpenseCategorySummaries()
       let cfg = categoryOrderMap[name]
       let target = cfg?.monthlyTarget.flatMap { Double($0) } // המרה מ-String ל-Double
       ```
    4. לבסוף, הפונקציה יוצרת ומוסיפה אובייקט `CategorySummary` למערך, עם היעד המומר (`target`) וסך ההוצאות שחושב (`totalSpent`).

---

## חלק 3: שכבת התצוגה (View)

`CashflowCardsView.swift` אחראי להציג את הנתונים למשתמש.

### 3.1. תצוגה ראשית
- ה-View מקבל את רשימת הקטגוריות המעובדות (`orderedItems`) מה-ViewModel.
- עבור כל קטגוריה, הוא משתמש ב-View ייעודי בשם `CategorySummaryCard`.

### 3.2. `CategorySummaryCard.swift`
- **מטרה**: להציג את המידע עבור קטגוריה בודדת.
- **לוגיקת התצוגה**:
    1. **חישוב התקדמות**: `CategorySummaryCard` מכיל משתנה מחושב שמחשב את ההתקדמות ביחס ליעד.
       ```swift
       private var progress: Double {
           guard let t = category.target, t > 0 else { return 0 }
           return category.totalSpent / t
       }
       ```
    2. **הצגת בר התקדמות**: הערך `progress` נשלח לקומפוננטה נוספת בשם `ProgressCapsule` שמציגה בר התקדמות ויזואלי.
    3. **הצגת יתרה**: הקוד בודק אם קיים יעד (`if let t = category.target`), ואם כן, הוא מציג למשתמש טקסט המציין כמה כסף נשאר להוציא או בכמה חרג מהיעד.
       ```swift
       // מתוך CategorySummaryCard
       if let t = category.target {
           let remain = max(t - category.totalSpent, 0)
           Text(category.totalSpent > t ? "חריגה של..." : "נשאר להוציא \(remain)...")
           // ...
       }
       ```

---
## סיכום
זוהי תוכנית היישום המלאה והמפורטת עבור הצגת היעדים באפליקציה. היא מתארת את זרימת המידע מקצה לקצה, החל משליפתו כ-String מה-API, דרך עיבודו ב-ViewModel, ועד להצגתו באופן גרפי ב-View.

אני מוכן להתחיל ביישום על פי תוכנית זו.
