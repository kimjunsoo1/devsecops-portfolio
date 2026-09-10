// 침투 테스트용 취약 코드. 실행하지 마세요.
// Semgrep 이 잡아야 하는 패턴들입니다.

const { exec } = require('child_process');

// 명령 주입 - 사용자 입력이 셸로 그대로 들어갑니다.
function listFiles(userPath) {
  exec(`ls -la ${userPath}`, (err, stdout) => {
    console.log(stdout);
  });
}

// eval - 임의 코드 실행
function calculate(expression) {
  return eval(expression);
}

// 하드코딩된 자격증명
const config = {
  apiKey: 'bGgYDvTx3YThpFGc5w3QF1SdEPI69xVCR01w4XAd',
  dbPassword: 'SuperSecret123!',
};

module.exports = { listFiles, calculate, config };
