"""
log_generator.py — Sinh dữ liệu test tối thiểu cho InfluxDB, mô phỏng *output* mà Spark Structured Streaming
sẽ ghi xuống theo tài liệu data-flow (cửa sổ 10s, metric theo status_class).

Đơn giản — chỉ một measurement duy nhất: `http_requests`
  • TAGS:   env, hostname, method, status_class (2xx|3xx|4xx|5xx)
  • FIELDS: count (int), rps (float), avg_rt (float giây), max_rt (float giây)
  • TS:     nanosecond epoch (sử dụng thời điểm *kết thúc* của mỗi cửa sổ)

Ví dụ 1 dòng (Line Protocol):
  http_requests,env=dev,hostname=web1,method=GET,status_class=2xx count=120i,rps=12,avg_rt=0.042,max_rt=0.23 1735872000000000000

Cách chạy tối giản (đọc cấu hình từ .env.influx hoặc truyền tham số):
  python log_generator.py \
    --url http://localhost:8086 --org demo-org --bucket http-logs --token $INFLUX_TOKEN \
    --duration 60 --qps 80 --hosts 3 --window 10 --envtag dev

Lưu ý:
- Script *không* sinh raw access log; nó sinh *metrics đã aggregate* đúng như "phần Spark cung cấp".
- rps = count / window_seconds.
- Bạn có thể điều chỉnh --err-rate (tổng lỗi 4xx+5xx) và --p5xx (tỷ lệ 5xx trong tổng request).
"""
from __future__ import annotations

import argparse
import gzip
import os
import random
import time
from typing import Dict, List, Tuple
from urllib import error, parse, request

# -------------------------
# Helpers
# -------------------------

def _esc_tag(v: str) -> str:
    """Escape tag theo Influx Line Protocol (space/comma/equals)."""
    return (
        v.replace("\\", r"\\\\")
         .replace(",", r"\\,")
         .replace(" ", r"\\ ")
         .replace("=", r"\\=")
    )


def _quote_str(v: str) -> str:
    return '"' + v.replace("\\", r"\\\\").replace('"', r"\\\"") + '"'


def line_protocol(measurement: str, tags: Dict[str, str], fields: Dict[str, object], ts_ns: int) -> str:
    tag_part = ",".join(f"{k}={_esc_tag(str(v))}" for k, v in tags.items() if v is not None)
    field_chunks: List[str] = []
    for k, v in fields.items():
        if isinstance(v, bool):
            field_chunks.append(f"{k}={(1 if v else 0)}i")
        elif isinstance(v, int):
            field_chunks.append(f"{k}={v}i")
        elif isinstance(v, float):
            field_chunks.append(f"{k}={format(v, 'g')}")  # tránh dạng khoa học
        else:
            field_chunks.append(f"{k}={_quote_str(str(v))}")
    field_part = ",".join(field_chunks)
    return f"{measurement},{tag_part} {field_part} {ts_ns}" if tag_part else f"{measurement} {field_part} {ts_ns}"


def now_ns() -> int:
    return time.time_ns()


def window_bounds_ns(t_ns: int, window_s: int) -> Tuple[int, int]:
    w = window_s * 1_000_000_000
    end = ((t_ns // w) + 1) * w
    start = end - w
    return start, end


# -------------------------
# Writer
# -------------------------
class InfluxWriter:
    def __init__(self, base_url: str, org: str, bucket: str, token: str, gzip_enable: bool = False, timeout: float = 10.0):
        self.base_url = base_url.rstrip('/')
        self.org = org
        self.bucket = bucket
        self.token = token
        self.gzip_enable = gzip_enable
        self.timeout = timeout

    def write(self, lines: List[str]) -> Tuple[int, str]:
        if not lines:
            return 204, "empty"
        payload = ("\n".join(lines)).encode("utf-8")
        headers = {
            "Authorization": f"Token {self.token}",
            "Content-Type": "text/plain; charset=utf-8",
        }
        if self.gzip_enable:
            payload = gzip.compress(payload)
            headers["Content-Encoding"] = "gzip"
        url = f"{self.base_url}/api/v2/write?" + parse.urlencode({
            "org": self.org,
            "bucket": self.bucket,
            "precision": "ns",
        })
        req = request.Request(url, data=payload, headers=headers, method="POST")
        try:
            with request.urlopen(req, timeout=self.timeout) as resp:
                return resp.getcode(), resp.read().decode("utf-8", "ignore")
        except error.HTTPError as e:
            return e.code, e.read().decode("utf-8", "ignore")
        except Exception as e:
            return -1, str(e)


# -------------------------
# Synthetic metrics (đơn giản, đủ dùng)
# -------------------------
METHODS = ["GET", "POST"]
STATUS_CLASSES = ["2xx", "3xx", "4xx", "5xx"]


def split_counts(total: int, err_rate: float, p5xx: float) -> Dict[str, int]:
    """Chia tổng request theo 2xx/3xx/4xx/5xx. Rất đơn giản: 3xx nhỏ, lỗi theo tham số."""
    if total <= 0:
        return {sc: 0 for sc in STATUS_CLASSES}
    total_err = max(0, min(1, err_rate)) * total
    cnt_5xx = int(round(max(0, min(p5xx, err_rate)) * total))
    cnt_4xx = int(round(total_err - cnt_5xx))
    cnt_3xx = max(0, int(round(0.05 * total)))  # 5% redirect giả lập
    cnt_2xx = max(0, total - (cnt_3xx + cnt_4xx + cnt_5xx))
    # chỉnh sai số nhỏ
    arr = [cnt_2xx, cnt_3xx, cnt_4xx, cnt_5xx]
    diff = total - sum(arr)
    for i in range(abs(diff)):
        arr[i % len(arr)] += 1 if diff > 0 else -1
    return {sc: arr[i] for i, sc in enumerate(STATUS_CLASSES)}


def pick_latency(count: int) -> Tuple[float, float]:
    """Trả (avg_rt, max_rt) đơn giản (giây)."""
    if count <= 0:
        return 0.0, 0.0
    avg_ms = max(5.0, random.gauss(60.0, 15.0))  # ~60ms
    max_ms = avg_ms * random.uniform(1.5, 3.5)
    return avg_ms / 1000.0, max_ms / 1000.0


# -------------------------
# Main
# -------------------------
def main():
    p = argparse.ArgumentParser(description="Minimal generator — mô phỏng output Spark (aggregate 10s)")
    # Kết nối
    p.add_argument('--url', default=os.getenv('INFLUX_URL', 'http://localhost:8086'))
    p.add_argument('--org', default=os.getenv('INFLUX_ORG', os.getenv('ORG_NAME', 'demo-org')))
    p.add_argument('--bucket', default=os.getenv('INFLUX_BUCKET', os.getenv('BUCKET_NAME', 'http-logs')))
    p.add_argument('--token', default=os.getenv('INFLUX_TOKEN', os.getenv('ADMIN_TOKEN', '')))
    # Sinh liệu
    p.add_argument('--envtag', default='dev', help='Giá trị tag env')
    p.add_argument('--hosts', type=int, default=3)
    p.add_argument('--host-prefix', default='web')
    p.add_argument('--duration', type=int, default=60, help='Tổng thời gian chạy (giây)')
    p.add_argument('--window', type=int, default=10, help='Kích thước cửa sổ giây (mặc định 10)')
    p.add_argument('--qps', type=float, default=50.0, help='Tổng QPS dự kiến (chia đều theo hosts)')
    p.add_argument('--err-rate', type=float, default=0.05, help='Tổng lỗi (4xx+5xx)')
    p.add_argument('--p5xx', type=float, default=0.01, help='Tỷ lệ 5xx trong tổng request')
    p.add_argument('--gzip', action='store_true', help='Bật nén gzip khi gửi')

    args = p.parse_args()
    assert args.token, "Thiếu --token hoặc INFLUX_TOKEN/ADMIN_TOKEN trong env"

    writer = InfluxWriter(args.url, args.org, args.bucket, args.token, gzip_enable=args.gzip)

    # Chuẩn bị danh sách host
    hosts = [f"{args.host_prefix}{i+1}" for i in range(max(1, args.hosts))]

    start_time = time.time()
    end_time = start_time + max(1, args.duration)
    window_s = max(1, args.window)

    sent_ok = 0
    sent_err = 0

    while time.time() < end_time:
        t_ns = now_ns()
        w_start, w_end = window_bounds_ns(t_ns, window_s)
        ts_ns = w_end  # dùng mốc cuối cửa sổ

        lines: List[str] = []
        # QPS chia đều cho hosts; mỗi window có req = qps * window
        total_per_window = int(round(args.qps * window_s))
        per_host = max(1, total_per_window // max(1, len(hosts)))

        for h in hosts:
            # Chọn method giả lập (GET chiếm đa số)
            method = 'GET' if random.random() < 0.8 else 'POST'
            split = split_counts(per_host, args.err_rate, args.p5xx)
            for status_class, cnt in split.items():
                avg_rt, max_rt = pick_latency(cnt)
                rps = (cnt / float(window_s)) if window_s > 0 else float(cnt)
                tags = {
                    'env': args.envtag,
                    'hostname': h,
                    'method': method,
                    'status_class': status_class,
                }
                fields = {
                    'count': int(cnt),
                    'rps': float(f"{rps:.6f}"),
                    'avg_rt': float(f"{avg_rt:.6f}"),
                    'max_rt': float(f"{max_rt:.6f}"),
                }
                lines.append(line_protocol('http_requests', tags, fields, ts_ns))

        code, msg = writer.write(lines)
        if code in (204, 200):
            sent_ok += 1
            print(f"[batch OK] lines={len(lines)} code={code}")
        else:
            sent_err += 1
            print(f"[batch ERR] code={code} msg={msg[:200]}")

        # Ngủ tới hết cửa sổ (đơn giản)
        now = time.time()
        sleep_s = (w_end / 1e9) - now
        if sleep_s > 0:
            time.sleep(min(sleep_s, 0.5))  # sleep ngắn để đỡ lệch

    total = sent_ok + sent_err
    ok_pct = (sent_ok * 100.0 / total) if total else 100.0
    print(f"[summary] batches={total} ok={sent_ok} err={sent_err} ok%={ok_pct:.1f}")


if __name__ == '__main__':
    main()
