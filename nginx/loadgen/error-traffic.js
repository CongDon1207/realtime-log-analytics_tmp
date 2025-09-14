import http from 'k6/http';
import { sleep } from 'k6';

// Lưu lượng thấp, chạy mặc định 5 phút. Có thể override bằng CLI: -d 10m -u 2
export const options = {
  vus: 1,
  duration: '5m',
};

// Lưu ý: Nginx chỉ ghi error.log khi lỗi upstream (/api). Endpoint /oops trả 500 nhưng không ghi error.log.
const targets = [
  'http://web1:8081/api',
  'http://web2:8082/api',
  'http://web3:8083/api',
];

export default function () {
  const t = targets[Math.floor(Math.random() * targets.length)];
  http.get(t);
  sleep(1);
}
