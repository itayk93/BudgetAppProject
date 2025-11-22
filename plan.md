# תוכנית הטמעה: הצגת יעדים חודשיים לקטגוריות

## הקדמה
המטרה היא להציג למשתמשים את יעד ההוצאה או צפי ההכנסה החודשי עבור כל קטגוריה, ולהראות את התקדמותם ביחס ליעד זה. התוכנית מתמקדת בלוגיקת התצוגה בלבד, בהתבסס על הקוד הקיים.

---

## חלק 1: אחזור נתונים (Backend ומסד נתונים)

לוגיקת אחזור הנתונים תתבסס על המבנה הקיים במסד הנתונים ועל נקודות הקצה ב-API.

### 1.1. מבנה מסד הנתונים
- **יעדים אישיים**: היעד החודשי עבור כל קטגוריה נשמר בעמודה `monthly_target` בטבלת `category_order`.
- **יעדים משותפים**: יעדים החלים על מספר קטגוריות נשמרים בטבלה `shared_category_targets`. הקישור מתבצע באמצעות העמודות `shared_category` ו-`use_shared_target` בטבלת `category_order`.

### 1.2. API Endpoint
נקודת הקצה העיקרית לאחזור נתוני הלוח הבקרה היא `api/dashboard.js`. קובץ זה אחראי על:
- שליפת כל הקטגוריות של המשתמש מהטבלה `category_order`.
- שליפת היעדים המשותפים הרלוונטיים מהטבלה `shared_category_targets`.
- אחזור כל העסקאות לחודש ולתזרים המזומנים שנבחר.
- חישוב הסכום שהוצא/התקבל בכל קטגוריה.
- הרכבת אובייקט תגובה (`categoryBreakdown`) המכיל את כל המידע הדרוש לתצוגה, כולל היעד החודשי (`monthly_target`) וההוצאה בפועל (`amount`).

### 1.3. שאילתות אחזור נתונים (דוגמאות מ-`api/dashboard.js`)

**אחזור קטגוריות ויעדים אישיים:**
```javascript
// From api/dashboard.js
const { data: categories, error: categoriesError } = await supabase
  .from('category_order')
  .select('*')
  .eq('user_id', userId)
  .order('display_order', { ascending: true });
```

**אחזור יעדים משותפים:**
```javascript
// From api/dashboard.js
const { data: sharedTargetsData, error: sharedTargetsError } = await supabase
  .from('shared_category_targets')
  .select('*')
  .eq('user_id', userId)
  .in('shared_category_name', sharedCategoryNames);
```

---

## חלק 2: לוגיקת תצוגה (Frontend)

התצוגה תטופל בעיקר בקומפוננטת `client/src/components/CategoryCard/CategoryCard.js`.

### 2.1. קומפוננטת `CategoryCard.js`
קומפוננטה זו תקבל את נתוני הקטגוריה (כולל היעד וההוצאה) ותהיה אחראית על הצגתם.

### 2.2. לוגיקת התצוגה
1.  **קביעת היעד האפקטיבי**:
    - אם `use_shared_target` מסומן כ-`true` ויעד משותף קיים, יוצג היעד מהטבלה `shared_category_targets`.
    - אחרת, יוצג היעד האישי מהעמודה `monthly_target`.

2.  **תצוגה שבועית**:
    - אם האפשרות `weekly_display` פעילה, היעד השבועי יחושב ויוצג לפי הנוסחה: `monthly_target * 7 / 30`.

3.  **חישוב התקדמות ויתרה**:
    - **אחוז התקדמות**: `(spent / effective_target) * 100`.
    - **סכום נותר**: `effective_target - spent`.

### 2.3. אלמנטים ויזואליים
התצוגה תכלול את האלמנטים הבאים להמחשת ההתקדמות:
- **בר התקדמות** (`<div className="monthly-progress-fill">`): רוחב הבר ייקבע על פי אחוז ההתקדמות.
- **טקסט דינמי**:
    - אם המשתמש עומד ביעד, יוצג טקסט כמו: "נשאר להוציא X ₪".
    - אם המשתמש חרג מהיעד, יוצג טקסט כמו: "חרגת מהיעד ב-Y ₪".
- **צבעים מותנים**: צבע בר ההתקדמות והטקסט הנלווה ישתנה בהתאם למצב ההתקדמות (`on-track`, `warning`, `over-target`) כדי לספק חיווי ויזואלי מהיר.
- **כפתור עריכה**: יופיע כפתור (`<i className="fas fa-edit"></i>` או `<i className="fas fa-plus"></i>`) שיאפשר למשתמש לערוך או להגדיר יעד, מה שיוביל לפתיחת המודל `MonthlyTargetModal`.

---

## סיכום
התהליך יזרום באופן הבא:
1.  היעדים נשמרים בטבלאות `category_order` ו-`shared_category_targets`.
2.  נקודת הקצה `api/dashboard.js` מאחזרת ומעבדת את הנתונים.
3.  קומפוננטת `CategoryCard.js` מקבלת את הנתונים המעובדים ומציגה אותם למשתמש באופן ויזואלי ואינטואיטיבי, כולל התקדמות, יתרות וחיוויים מבוססי צבע.
