# ✅ CORRECTED FLUX QUERIES

## Query gốc (SAI):
```flux
from(bucket: "logs") 
|> range(start: -1h) 
|> filter(fn: (r) => r._measurement == "error_events" and (r.level == "ERROR" or r.level == "CRIT")) 
|> sort(columns: ["_time"], desc: true)
```

## Query đã sửa (ĐÚNG):
```flux
# Chỉ lấy error level (hiện tại chỉ có "error" trong data)
from(bucket: "logs") 
|> range(start: -1h) 
|> filter(fn: (r) => r._measurement == "error_events" and r.level == "error") 
|> sort(columns: ["_time"], desc: true)
```

## Nếu muốn filter multiple levels trong tương lai:
```flux
from(bucket: "logs") 
|> range(start: -1h) 
|> filter(fn: (r) => r._measurement == "error_events") 
|> filter(fn: (r) => r.level == "error" or r.level == "critical" or r.level == "fatal")
|> sort(columns: ["_time"], desc: true)
```

## Current data structure:
- level: "error" (lowercase)
- message_class: "timeout" 
- hostname: "localhost:8081", "localhost:8082", "localhost:8083"

## Lỗi trong query gốc:
1. ❌ Tìm "ERROR"/"CRIT" nhưng data có "error" 
2. ❌ Cú pháp and/or operator chưa đúng
3. ✅ Logic sort và range đúng