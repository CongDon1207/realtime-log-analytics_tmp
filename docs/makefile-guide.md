# 📘 Hướng dẫn cài & sử dụng Makefile trên Windows

## 1) Cài đặt `make`

Windows mặc định không có sẵn `make`. Cách đơn giản là cài qua Scoop.

### Bước 1. Cài Scoop (PowerShell, user thường)

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
```

### Bước 2. Cài `make`

```powershell
scoop install make
```

### Bước 3. Kiểm tra

```powershell
make --version
```

Kết quả mong đợi (ví dụ):

```
GNU Make 4.4.1
```

---

## 2) Dùng `make` trong Git Bash (MINGW64)

Nếu bạn chạy trong PowerShell thì dùng được ngay. Với Git Bash, đôi khi báo `make: command not found` do thiếu PATH tới Scoop shims.

Thêm dòng sau vào `~/.bashrc` (ổn định hơn khi dùng tên người dùng động):

```bash
export PATH="$PATH:$HOME/scoop/shims"
```

Sau đó nạp lại cấu hình và kiểm tra:

```bash
source ~/.bashrc
make --version
```

---

## 3) Makefile trong dự án

Tại thư mục gốc `realtime-log-analytics/` có (hoặc bạn có thể tạo) file `Makefile`. Ví dụ nội dung tham khảo:

```makefile
COMPOSE_DON = docker-compose.don.yml
COMPOSE_NGINX = docker-compose.nginx.yml

.PHONY: up-don down-don up-nginx down-nginx ps logs-don

up-don:
	docker compose -f $(COMPOSE_DON) up -d

down-don:
	docker compose -f $(COMPOSE_DON) down

up-nginx:
	docker compose -f $(COMPOSE_NGINX) up -d

down-nginx:
	docker compose -f $(COMPOSE_NGINX) down

ps:
	docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs-don:
	docker compose -f $(COMPOSE_DON) logs -f
```

Lưu ý quan trọng: Mỗi lệnh trong rule phải bắt đầu bằng ký tự Tab (không phải space).

---

## 4) Cách sử dụng

Đứng tại thư mục dự án rồi chạy:

- Khởi động InfluxDB stack:

```bash
make up-don
```

- Tắt InfluxDB stack:

```bash
make down-don
```

- Khởi động 3 web server Nginx (nếu có file compose tương ứng):

```bash
make up-nginx
```

- Tắt 3 web server Nginx:

```bash
make down-nginx
```

- Xem trạng thái container:

```bash
make ps
```

- Xem log InfluxDB:

```bash
make logs-don
```

---

## 5) Gỡ lỗi nhanh

- `make: command not found` trong Git Bash → đảm bảo đã thêm `$HOME/scoop/shims` vào PATH như mục 2.
- Lỗi 127 khi chạy target (ví dụ `up-don`) → thường là do `docker` không có trong PATH hoặc Docker Desktop chưa chạy. Kiểm tra bằng:

```bash
docker --version
```

- Nếu `docker-compose.nginx.yml` chưa tồn tại, bỏ hoặc thay thế các target `*-nginx` cho phù hợp repo của bạn.

---

Nếu bạn muốn, mình có thể thêm một target `loadgen` để chạy k6 tự động (theo tài liệu hướng dẫn k6/nginx).
