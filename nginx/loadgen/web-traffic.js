import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  vus: 50,
  duration: '60s',
};

const targets = [
  'http://web1:8081/',
  'http://web2:8082/',
  'http://web3:8083/',
];

export default function () {
  const t = targets[Math.floor(Math.random() * targets.length)];
  http.get(t);
  sleep(0);
}
