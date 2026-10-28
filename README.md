# RQ Kitchen — تتبع الطلب (track.rqkitchen.app)
- /cashier : شاشة الكاشير (رمز الدخول من جدول track_settings في Supabase)
- /o/<id>  : صفحة العميل بعد مسح الرمز
- الخلفية: Supabase edge function `track` + جداول track_orders / track_subs / track_settings
