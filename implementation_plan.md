# תוכנית להטמעת קטגוריות-על באפליקציית iOS

## 1. מבוא

מטרת תוכנית זו היא להטמיע מערכת היררכית של קטגוריות, המאפשרת למשתמשים לקבץ מספר "תת-קטגוריות" תחת "קטגוריית-על" אחת. התנהגות זו תתבסס על הלוגיקה הקיימת בפרויקט הרשת, עם התאמות נדרשות לסביבת Swift ו-SwiftUI.

הפיצ'ר יאפשר:
-   קיבוץ ויזואלי של קטגוריות קשורות (למשל, "שופרסל", "ירקות" ו"בשר" תחת קטגוריית-על "סופרמרקט").
-   הצגת סכום כולל ומספר עסקאות מאוחד עבור כל קטגוריית-על.
-   סידור קטגוריית-העל ברשימה על פי המיקום של תת-הקטגוריה הראשונה שבה.

---

## 2. שינויים במודלים של הנתונים (Models)

כדי לתמוך בקשר בין קטגוריות, נבצע את השינויים הבאים במודלים הקיימים:

1.  **הרחבת המודל `Category.swift` (או `CategoryOrder.swift`):**
    -   נוסיף מאפיין חדש מסוג `String?` בשם `parentCategoryName`.
    -   מאפיין זה יכיל את שם קטגוריית-העל. אם הוא ריק (`nil`), הקטגוריה תחשב לקטגוריה רגילה ועצמאית.

    ```swift
    struct Category: Identifiable, Codable {
        // ... (מאפיינים קיימים)
        var parentCategoryName: String?
    }
    ```

2.  **יצירת מודל חדש עבור קטגוריית-על: `ParentCategory.swift`**
    -   ניצור `struct` חדש שייצג את קטגוריית-העל המקובצת. הוא יכיל את הנתונים המאוחדים של כל תת-הקטגוריות שלו.

    ```swift
    struct ParentCategory: Identifiable {
        let id = UUID()
        let name: String
        var subCategories: [Category]
        var totalAmount: Double {
            subCategories.reduce(0) { $0 + $1.amount }
        }
        var totalTransactions: Int {
            subCategories.reduce(0) { $0 + $1.count }
        }
        // המיקום של קטגוריית העל יקבע ע"י המיקום הנמוך ביותר מבין תת הקטגוריות
        var displayOrder: Int {
            subCategories.map { $0.displayOrder }.min() ?? 999
        }
    }
    ```

3.  **יצירת `Enum` לייצוג אחיד ברשימה: `DisplayableItem`**
    -   כדי להציג רשימה המשלבת קטגוריות-על וקטגוריות רגילות, ניצור `enum` שיעטוף את שני הסוגים. זה יפשט את הלוגיקה ב-View.

    ```swift
    enum DisplayableItem: Identifiable {
        case parent(ParentCategory)
        case single(Category)

        var id: String {
            switch self {
            case .parent(let category):
                return category.name
            case .single(let category):
                return category.id
            }
        }

        var displayOrder: Int {
            switch self {
            case .parent(let category):
                return category.displayOrder
            case .single(let category):
                return category.displayOrder
            }
        }
    }
    ```

---

## 3. לוגיקה ב-ViewModel

ה-`CashFlowDashboardViewModel.swift` יהיה אחראי על עיבוד רשימת הקטגוריות השטוחה ויצירת המבנה ההיררכי לתצוגה.

-   **פונקציה חדשה: `groupCategories`**
    -   הפונקציה תקבל מערך של כל הקטגוריות (`[Category]`).
    -   היא תיצור שני אוספים:
        1.  רשימה של קטגוריות עצמאיות (אלה ללא `parentCategoryName`).
        2.  מילון (`[String: [Category]]`) שיקבץ את תת-הקטגוריות לפי שם קטגוריית-העל שלהן.
    -   לאחר מכן, הלוגיקה תעבור על המילון ותיצור אובייקטים של `ParentCategory` עבור כל קבוצה.
    -   לבסוף, הפונקציה תחזיר מערך מאוחד של `[DisplayableItem]`, המכיל גם קטגוריות-על וגם קטגוריות רגילות, ממוינות לפי `displayOrder`.

---

## 4. יישום בממשק המשתמש (Views)

השינוי העיקרי יהיה ב-`CashflowCardsView.swift` ובנוסף ניצור קומפוננטה חדשה.

1.  **עדכון `CashflowCardsView.swift`:**
    -   הרשימה הראשית (כנראה `ForEach`) תעבור על מערך ה-`[DisplayableItem]` שקיבלנו מה-ViewModel.
    -   נשתמש ב-`switch` על כל `item` כדי להחליט איזה View להציג:
        -   אם `item` הוא `.parent`, נציג `ParentCategoryView` חדש.
        -   אם `item` הוא `.single`, נציג את ה-`CategoryCardView` הקיים.

2.  **קומפוננטה חדשה: `ParentCategoryView.swift`:**
    -   זהו View חדש שיוקדש להצגת קטגוריית-על.
    -   הוא יציג את שם קטגוריית-העל, הסכום הכולל, ומספר העסקאות הכולל.
    -   **התנהגות אינטראקטיבית:** ה-View יהיה ניתן ללחיצה. לחיצה עליו תרחיב/תכווץ אותו (`isExpanded`) ותציג/תסתיר את רשימת תת-הקטגוריות שבו.
    -   כאשר הוא מורחב, הוא יציג את תת-הקטגוריות שלו (ניתן להשתמש ב-`CategoryCardView` קיים עם עיצוב מוזח קלות כדי לציין היררכיה).

---

## 5. מסך ניהול וקישור קטגוריות

בדומה לקובץ `CategoryOrder.js` מהפרויקט האינטרנטי, יש צורך במסך ייעודי שבו המשתמש יוכל לנהל את הקישורים.

-   **יצירת מסך חדש: `EditCategoryOrderView.swift`:**
    -   המסך יציג רשימה של כל הקטגוריות של המשתמש.
    -   לצד כל קטגוריה, יופיע כפתור "שייך לקטגוריית-על".
    -   לחיצה על הכפתור תפתח `Picker` או מסך בחירה שיאפשר למשתמש:
        1.  לבחור קטגוריית-על קיימת מהרשימה.
        2.  להקליד שם וליצור קטגוריית-על חדשה.
        3.  לבטל את השיוך.
    -   השינויים יישמרו דרך ה-`CategoryOrderService`, שיצטרך להכיל פונקציה חדשה לעדכון המאפיין `parentCategoryName`.

---

## 6. סיכום תהליך היישום

1.  **מודלים:** הוספת `parentCategoryName` למודל הקיים ויצירת מודלים חדשים (`ParentCategory`, `DisplayableItem`).
2.  **ViewModel:** הטמעת לוגיקת הקיבוץ והמיון ב-`CashFlowDashboardViewModel`.
3.  **Views:**
    -   יצירת `ParentCategoryView.swift` לתצוגת קטגוריית-על מתקפלת.
    -   התאמת `CashflowCardsView.swift` להצגת הרשימה ההיררכית.
4.  **ניהול:** בניית מסך `EditCategoryOrderView.swift` שיאפשר למשתמשים ליצור ולנהל את הקישורים.

לאחר אישורך, אתחיל בביצוע השלבים הללו.
