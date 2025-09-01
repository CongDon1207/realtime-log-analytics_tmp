#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse, os, sys, time, random, math
from pathlib import Path
import requests
from dotenv import dotenv_values

def load_env(gen_env_path: Path):
    # Load .env.gen
    gen_cfg = dotenv_values(gen_env_path)

    # Load token from TOKEN_FILE (if provided)
    token = gen_cfg.get("ADMIN_TOKEN", "")
    token_file = gen_cfg.get("TOKEN_FILE", "")
    if (not token) and token_file:
        env_path = (gen_env_path.parent / token_file).resolve()
        if env_path.exists():
            infl = dotenv_values(env_path)
            token = infl.get("ADMIN_TOKEN", "")

    cfg = {
        "qps": int(gen_cfg.get("GEN_QPS", "50")),
        "duration": int(gen_cfg.get("GEN_DURATION", "60")),
        "apps": [x for x in gen_cfg.get("GEN_APPS", "web").split(",") if x],
        "env": gen_cfg.get("GEN_ENV", "dev"),
        "hosts": int(gen_cfg.get("GEN_HOSTS", "3")),
        "paths": gen_cfg.get("GEN_PATHS", "/ /api /login").split(),
        "url": gen_cfg.get("INFLUX_URL", "http://localhost:8086"),
        "org": gen_cfg.get("ORG_NAME", "demo-org"),
        "bucket": gen_cfg.get("BUCKET_NAME", "http-logs"),
        "token": token,
    }
    # Basic checks
    if not cfg["token"]:
        print("[ERROR] ADMIN_TOKEN rỗng. Điền ADMIN_TOKEN trong .env.gen hoặc cung cấp TOKEN_FILE trỏ tới influxdb/.env.influx", file=sys.stderr)
        sys.exit(2)
    return cfg

def pick_status():
    """
    Phân phối status [Giả định]:
    - 92%: 2xx
    - 6% : 4xx
    - 2% : 5xx
    """
    r = random.random()
    if r < 0.92:
        return random.choice([200, 200, 200, 201, 204])
    elif r < 0.98:
        return random.choice([400, 401, 403, 404, 429])
    else:
        return random.choice([500, 502, 503])

def sample_latency_ms():
    """
    Latency log-normal (mean~50ms, tail dài) [Giả định]
    """
    # lognormal với mu, sigma chọn kinh nghiệm
    val = random.lognormvariate(math.log(50), 0.6)
    return max(1.0, min(val, 3000.0))

def sample_bytes(status):
    if 200 <= status < 300:
        return random.randint(800, 5000)
    elif 400 <= status < 500:
        return random.randint(200, 1200)
    else:
        return random.randint(100, 600)

def build_line(measurement, tags: dict, fields: dict, ts_ns: int) -> str:
    # Escape tag/field keys/values tối thiểu
    def esc_tag(v: str) -> str:
        return v.replace(" ", "\\ ").replace(",", "\\,").replace("=", "\\=")
    def esc_field_str(v: str) -> str:
        return v.replace('"', '\\"')

    tag_str = ",".join([f"{k}={esc_tag(str(v))}" for k, v in tags.items()])
    field_parts = []
    for k, v in fields.items():
        if isinstance(v, int):
            field_parts.append(f"{k}={v}i")
        elif isinstance(v, float):
            field_parts.append(f"{k}={('{:.3f}'.format(v)).rstrip('0').rstrip('.')}")
        elif isinstance(v, str):
            field_parts.append(f'{k}="{esc_field_str(v)}"')
        else:
            raise ValueError("Unsupported field type")
    field_str = ",".join(field_parts)
    return f"{measurement},{tag_str} {field_str} {ts_ns}"

def main():
    parser = argparse.ArgumentParser(description="HTTP logs generator → InfluxDB v2 write API")
    parser.add_argument("--qps", type=int, help="records per second (default from .env.gen)")
    parser.add_argument("--duration", type=int, help="seconds to run")
    parser.add_argument("--apps", nargs="+", help="list of app names")
    parser.add_argument("--env", dest="env_name", help="env tag value")
    parser.add_argument("--hosts", type=int, help="number of hosts")
    parser.add_argument("--paths", nargs="+", help="list of url paths")
    parser.add_argument("--gzip", action="store_true", help="enable gzip for payload")
    parser.add_argument("--measurement", default="http_requests", help="measurement name")
    args = parser.parse_args()

    gen_env_path = Path(__file__).parent / ".env.gen"
    cfg = load_env(gen_env_path)

    qps       = args.qps if args.qps else cfg["qps"]
    duration  = args.duration if args.duration else cfg["duration"]
    apps      = args.apps if args.apps else cfg["apps"]
    env_name  = args.env_name if args.env_name else cfg["env"]
    hosts_n   = args.hosts if args.hosts else cfg["hosts"]
    paths     = args.paths if args.paths else cfg["paths"]
    meas      = args.measurement
    enable_gzip = bool(args.gzip)

    org = cfg["org"]; bucket = cfg["bucket"]; token = cfg["token"]; base_url = cfg["url"]

    write_url = f"{base_url}/api/v2/write?org={org}&bucket={bucket}&precision=ns"
    headers = {
        "Authorization": f"Token {token}",
        "Content-Type": "text/plain"
    }
    if enable_gzip:
        headers["Content-Encoding"] = "gzip"

    hosts = [f"server-{i}" for i in range(1, hosts_n + 1)]
    methods = ["GET", "POST"]

    print(f"[gen] Start: qps={qps}, duration={duration}s, apps={apps}, env={env_name}, hosts={hosts_n}, paths={paths}")
    print(f"[gen] Target: {write_url}")
    total = ok = fail = 0

    session = requests.Session()
    start = time.time()
    end = start + duration

    batch = []
    batch_target = min(max(qps // 5, 100), 5000)  # 5 ticks/second; 100..5000
    next_tick = start

    while time.time() < end:
        # tick pacing: aim 5 ticks per second
        now = time.time()
        if now < next_tick:
            time.sleep(min(next_tick - now, 0.01))
            continue
        next_tick += 0.2  # 5 ticks/sec

        # generate roughly qps/5 records per tick
        per_tick = max(1, qps // 5)
        for _ in range(per_tick):
            app = random.choice(apps)
            host = random.choice(hosts)
            path = random.choice(paths)
            method = random.choice(methods)
            status = pick_status()
            latency = sample_latency_ms()
            by = sample_bytes(status)
            ts_ns = time.time_ns()  # UTC ns

            tags = {
                "app": app,
                "env": env_name,
                "host": host,
                "method": method,
                "path": path,
                "status": status
            }
            fields = {
                "latency_ms": float(latency),
                "bytes": int(by),
                "count": 1
            }
            lp = build_line(meas, tags, fields, ts_ns)
            batch.append(lp)
            total += 1

        # flush if big enough or last loop
        if len(batch) >= batch_target or time.time() + 0.25 >= end:
            data = ("\n".join(batch)).encode("utf-8")
            try:
                resp = session.post(write_url, headers=headers, data=data, timeout=10)
                if resp.status_code == 204:
                    ok += len(batch)
                else:
                    fail += len(batch)
                    # Không in token; chỉ mã lỗi và vài ký tự body
                    print(f"[gen][WARN] write HTTP {resp.status_code} body={resp.text[:200]}")
            except Exception as e:
                fail += len(batch)
                print(f"[gen][ERROR] {e}")
            finally:
                batch = []

    elapsed = time.time() - start
    print(f"[gen] Done in {elapsed:.1f}s — sent={total}, ok={ok}, fail={fail}, ok%={(ok/max(total,1))*100:.1f}")
    # kỳ vọng HTTP 204 khi thành công
    if fail == 0:
        print("[gen] Result: SUCCESS (HTTP 204 on writes)")
    else:
        print("[gen] Result: PARTIAL/FAIL — check warnings above")
    # [Chưa xác minh]
if __name__ == "__main__":
    main()
