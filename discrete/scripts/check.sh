#!/usr/bin/env bash
# 增强版 check.sh — 不靠日志安静期猜状态，直接打:
#   进程 / 线程(证明挖矿线程跑满) / 端口 / RPC getinfo & getheight / wallet 文件 / 日志尾
#
# 用法: bash scripts/check.sh

set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; nc='\033[0m'
ok="${green}[OK]${nc}"; warn="${yellow}[!]${nc}"; bad="${red}[X]${nc}"

echo -e "==== ${green}discreted 进程 ${nc}===="
PID=""
if [[ -f run/discreted.pid ]]; then
  PID="$(cat run/discreted.pid)"
fi
if [[ -z "${PID}" ]]; then
  PID="$(pgrep -f "bin/discreted" | head -1)"
fi
if [[ -n "${PID}" ]] && kill -0 "${PID}" 2>/dev/null; then
  echo -e "  ${ok} PID=${PID}  运行时长: $(ps -o etime= -p ${PID} 2>/dev/null | tr -d ' ')"
  echo -e "  ${ok} CPU%:    $(ps -o %cpu= -p ${PID} 2>/dev/null | tr -d ' ')"
  echo -e "  ${ok} MEM%:    $(ps -o %mem= -p ${PID} 2>/dev/null | tr -d ' ')  RSS≈$(ps -o rss= -p ${PID} 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')"
  echo ""
  echo -e "  ${green}👉 线程列表 (前 20 行): 主进程 1 个调度 + N 个 99.x% 的 = 挖矿线程数${nc}"
  printf "    %-8s %-8s %-8s %-8s %s\n" "PID" "LWP" "ELAPSED" "%CPU" "COMMAND"
  ps -L -p "${PID}" -o pid=,lwp=,etime=,pcpu=,comm= 2>/dev/null | head -20 | awk '{printf "    %-8s %-8s %-8s %-8s %s\n", $1,$2,$3,$4,$5}'
  NTHREADS=$(ps -L -p "${PID}" -o lwp= 2>/dev/null | wc -l)
  FULL_THREADS=$(ps -L -p "${PID}" -o pcpu= 2>/dev/null | awk '{if ($1+0>90) c++} END{print c+0}')
  echo ""
  echo -e "  ${ok} 总线程数 = ${NTHREADS};   CPU≥90% 的线程数 = ${FULL_THREADS}  (这个数字 ≈ 你 --mining-threads 的值就对了)"
else
  echo -e "  ${bad} discreted 进程未运行 (pid 文件: ${PID:-none})"
  echo "    👉 启动: bash scripts/step4-start-mining.sh 4"
fi

echo ""
echo -e "==== ${green}端口 (P2P 9330 / RPC 9331) ${nc}===="
for port in 9330 9331; do
  if (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -qE ":${port}\\b"; then
    echo -e "  ${ok} :${port} LISTEN  ($([ "${port}" = "9330" ] && echo "P2P 公网入站" || echo "RPC 本地回环"))"
  else
    echo -e "  ${bad} :${port} 未监听"
  fi
done

echo ""
echo -e "==== ${green}链实时状态 (RPC 127.0.0.1:9331/getinfo) ${nc}===="
INFO_JSON="$(curl -s --max-time 5 http://127.0.0.1:9331/getinfo 2>/dev/null)"
H_JSON="$(curl -s --max-time 5 http://127.0.0.1:9331/getheight 2>/dev/null)"
if [[ -n "${INFO_JSON}" ]] && echo "${INFO_JSON}" | grep -q "difficulty"; then
  HEIGHT=$(echo   "${H_JSON}"    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('height','?'))" 2>/dev/null || echo "?")
  STATUS=$(echo   "${H_JSON}"    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('status','?'))" 2>/dev/null || echo "?")
  DIFF=$(echo     "${INFO_JSON}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('difficulty','?'))" 2>/dev/null || echo "?")
  CUM=$(echo      "${INFO_JSON}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('cumulative_difficulty','?'))" 2>/dev/null || echo "?")
  COINS=$(echo    "${INFO_JSON}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('already_generated_coins','?'))" 2>/dev/null || echo "?")
  ALT=$(echo      "${INFO_JSON}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('alt_blocks_count','?'))" 2>/dev/null || echo "?")
  GREY=$(echo     "${INFO_JSON}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('grey_peerlist_size','?'))" 2>/dev/null || echo "?")
  WHITE=$(echo    "${INFO_JSON}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('white_peerlist_size','?'))" 2>/dev/null || echo "?")
  IN_CN=$(echo    "${INFO_JSON}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('incoming_connections_count','?'))" 2>/dev/null || echo "?")
  OUT_CN=$(echo   "${INFO_JSON}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('outgoing_connections_count','?'))" 2>/dev/null || echo "?")
  CONN=$(( ${IN_CN:-0} + ${OUT_CN:-0} ))
  echo -e "  ${ok} 链高度 Height:                  ${HEIGHT}"
  echo -e "  ${ok} 状态 status:                    ${STATUS}"
  echo -e "  ${ok} 当前难度 difficulty:            ${DIFF}      (你的 H/s / 难度 ≈ 出块秒数)"
  echo -e "  ${ok} 累计难度 cumulative_difficulty: ${CUM}"
  echo -e "  ${ok} 已生成总币:                     ${COINS} DCRT"
  echo -e "  ${ok} 孤块 alt_blocks:                ${ALT}"
  echo -e "  ${ok} 对端 peer (入=${IN_CN} + 出=${OUT_CN} = ${CONN} 活连接;  白名单=${WHITE}  灰名单=${GREY})"
  if [[ "${CONN}" -eq 0 ]] 2>/dev/null; then
    echo -e "  ${warn} 对端 peer 为 0 —— 可能防火墙挡住 9330 出方向, 或网络受限"
  fi
else
  echo -e "  ${bad} RPC 未返回 getinfo —— 进程可能未启动 / 正在启动中"
fi

echo ""
echo -e "==== ${green}钱包文件 wallet/ ${nc}===="
if [[ -d wallet/ ]]; then
  # Discrete v0.9.5 的 simplewallet 默认把 keys 合并进 miner.wallet 单文件内（不需要独立 .keys）.
  # 所以只检查: miner.wallet (主体, ≥80KB 视为含键) + password + seed 三件套.
  (
    printf "  %-22s %-9s %-11s %-4s  %s\n" "FILE" "STATUS" "SIZE(B)" "" "MTIME"
    for f in wallet/miner.wallet wallet/miner-password.txt wallet/miner-seed.txt wallet/miner.wallet.address; do
      if [[ -f "${f}" ]]; then
        extra=""
        if [[ "${f}" == "wallet/miner.wallet" ]]; then
          sz="$(stat -c%s "${f}" 2>/dev/null)"
          if   [[ "${sz:-0}" -ge 200000 ]]; then extra="(含密钥+链数据, ✅正常)";
          elif [[ "${sz:-0}" -ge 80000 ]];  then extra="(含密钥, ✅正常)";
          else                                  extra="(⚠️小, 密码对吗? 建议验证: simplewallet --wallet-file ${f} --password ... --command balance)"; fi
        fi
        printf "  ${ok} %-20s %-9s %-11s %-4s  %s %s\n" "${f}" "OK" "$(stat -c%s "${f}" 2>/dev/null)" "" "$(stat -c%y "${f}" 2>/dev/null | cut -c1-16)" "${extra}"
      else
        if [[ "${f}" == "wallet/miner.wallet.address" ]]; then
          # address 文件只是缓存输出, 不是必需
          printf "  ${warn} %-20s %-9s %-11s %-4s  %s\n" "${f}" "可选" "-" "" "(非必需, 打开钱包时自动生成)"
        else
          printf "  ${bad} %-20s %-9s %-11s %-4s  %s\n" "${f}" "缺失" "-" "" "(必填项, 请参考 STEPS.md 补全)"
        fi
      fi
    done
  )
  echo ""
  echo -e "  💡 强验证钱包 (密码对/链数据好):  ${green}bin/simplewallet --wallet-file wallet/miner.wallet --password \"\$(cat wallet/miner-password.txt)\" --daemon-address 127.0.0.1:9331 --command balance${nc}"
else
  echo -e "  ${bad} wallet/ 目录不存在"
fi

echo ""
echo -e "==== ${green}data/ 大小 (随同步增长; 挖矿时变化不大) ${nc}===="
du -sh data/ 2>/dev/null || echo -e "  ${bad} 无法读取 data/"

echo ""
echo -e "==== ${green}小工具速查 ${nc}===="
echo -e "  启动挖矿(先停旧):  ${green}bash scripts/step4-start-mining.sh${nc}   (默认=物理核数; 手动覆盖: $0 16)"
echo -e "  停止(优雅):        ${green}bash scripts/stop.sh${nc}"
echo -e "  实时跟日志:        ${green}tail -f logs/discreted.log${nc}   (挖到块 / 连断 peer / 报错 才写)"
echo -e "  日志最后写入时间:  $( [[ -f logs/discreted.log ]] && stat -c%y logs/discreted.log 2>/dev/null | cut -c1-19 || echo '(log 不存在)' )   (只打事件, 所以安静是正常的)"
echo -e "  重跑本检查:        ${green}bash scripts/check.sh${nc}"
