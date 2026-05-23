#!/bin/bash 

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# ---------- 容器适配 ----------
is_container() {
    [ -f /.dockerenv ] || grep -Eq '(docker|containerd|lxc|kubepods)' /proc/1/cgroup 2>/dev/null
}

# root 在容器内无需 sudo
sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        command sudo "$@"
    fi
}

CLASH_DIR="${CLASH_DIR:-/etc/clash}"
CLASH_BIN="${CLASH_BIN:-/usr/local/clash}"
CLASH_PORT="${CLASH_PORT:-7890}"

# 设置全局变量
export config_file="${CLASH_DIR}/config.yaml"

current_script_version=4.9.3-container.2
CLASH_RUN_STATE="${CLASH_DIR}/.run_state"

set_clash_run_state() {
    echo "$1" | sudo tee "${CLASH_RUN_STATE}" > /dev/null
}

clash_run_wanted() {
    [ -x "${CLASH_BIN}" ] || return 1
    [ -f "${CLASH_DIR}/config.yaml" ] || return 1
    case "$(sudo cat "${CLASH_RUN_STATE}" 2>/dev/null | tr -d '[:space:]')" in
        off) return 1 ;;
        *) return 0 ;;
    esac
}

setup_autostart() {
    if is_container; then
        local hook="/etc/profile.d/clash-autostart.sh"
        sudo tee "$hook" > /dev/null << EOF
# Clash autostart for container (respects ${CLASH_RUN_STATE}: on|off)
_clash_run_wanted() {
    [ -x ${CLASH_BIN} ] || return 1
    [ -f ${CLASH_DIR}/config.yaml ] || return 1
    case "\$(cat ${CLASH_RUN_STATE} 2>/dev/null | tr -d '[:space:]')" in
        off) return 1 ;;
        *) return 0 ;;
    esac
}
_clash_autostart() {
    _clash_run_wanted || return
    pgrep -f "${CLASH_BIN}.*-d.*${CLASH_DIR}" >/dev/null 2>&1 && return
    setsid ${CLASH_BIN} -d ${CLASH_DIR} >> /dev/null 2>&1 &
}
_clash_autostart
unset -f _clash_run_wanted _clash_autostart
EOF
        sudo chmod 644 "$hook"
        sudo touch "${CLASH_DIR}/.container_mode"
        # 首次迁移：无状态文件时按当前进程是否存活初始化
        if [ ! -f "${CLASH_RUN_STATE}" ]; then
            if pgrep -f "${CLASH_BIN}.*-d.*${CLASH_DIR}" >/dev/null 2>&1; then
                set_clash_run_state on
            else
                set_clash_run_state off
            fi
        fi
        # 容器内 crontab @reboot 通常无效，清理旧条目
        if crontab -l 2>/dev/null | grep -q "clash -d"; then
            crontab -l 2>/dev/null | grep -v "clash -d" | crontab -
        fi
    else
        (crontab -l 2>/dev/null | grep -v "clash -d"; echo "@reboot ${CLASH_BIN} -d ${CLASH_DIR} >> /dev/null 2>&1") | crontab -
    fi
}

remove_autostart() {
    if is_container; then
        sudo rm -f /etc/profile.d/clash-autostart.sh
        sudo rm -f "${CLASH_DIR}/.container_mode"
    else
        crontab -l 2>/dev/null | grep -v "clash -d" | crontab -
    fi
}

update_script() {
    # 使用传递的参数作为选择
    local auto="$1"  # 将参数作为选择
	if [[ ! -n $auto ]]; then
		echo -e "正在检测脚本版本，请稍候..."
	elif [ -f "${CLASH_DIR}/.last_update_script" ] && (( $(date +%s) - $(cat "${CLASH_DIR}/.last_update_script") < 2592000 )); then
        if [[ ! -n $res && -n $2 ]]; then
        	res="$2"
        fi
		return                                                         
	fi

	# 下载脚本文件
	downloadlink=$(cat "${CLASH_DIR}/.downloadlink")
	URL="$downloadlink/app-download/linux_script.sh"
	temp_file="${CLASH_DIR}/script.sh"

    # 设置超时时间为5秒
    sudo wget --timeout=5 -q -O $temp_file $URL

    # 检查下载是否成功
    if [ $? -eq 0 ]; then
		# 提取脚本内的script_version
		remote_script_version=$(grep "current_script_version" "$temp_file" | head -n 1)
		remote_script_version="${remote_script_version#*=}"  # 截取=后面的内容

    	if is_container && [[ "$remote_script_version" > "$current_script_version" ]]; then
			res="${yellow}容器模式：已跳过在线脚本升级（远程脚本会覆盖容器适配）。当前版本：${current_script_version}${plain}"
			sudo rm -f "$temp_file"
		elif [[ "$remote_script_version" > "$current_script_version" ]]; then
			sudo mv -f "$temp_file" "${CLASH_DIR}/linux_script.sh"
			sudo chmod +x "${CLASH_DIR}/linux_script.sh"
			res="${green}脚本升级成功，旧版本：${red}${current_script_version}${green} -> 新版本：${red}${remote_script_version}${plain}"
			sudo sh -c "echo \"\$(date +%s)\" > ${CLASH_DIR}/.last_update_script"
			exec "${CLASH_DIR}/linux_script.sh" "$res"
		else
			res="${green}当前脚本版本：${red}$current_script_version${green}，脚本已是最新版本，无需升级。${plain}"
		fi
    fi
}

arch=$(arch)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
   arch="amd64"
elif [[ $arch == "i686" || $arch == "i386" ]]; then
   arch="386"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
   arch="arm64"
else
   arch="amd64"
   echo -e "${red}检测架构失败，将使用默认架构: ${arch}${plain}"
   read
fi

pre_setup () {
    if [ -e "${CLASH_BIN}" ]; then
		read -p "您的电脑已经安装了Clash，是否重装？输入Y/y重装：" isReinstall
		if [[ $isReinstall != "Y" && $isReinstall != "y" ]]; then
			exit 1 # 退出脚本，返回非零状态码
		fi
    fi
   	echo -e "${green}开始安装...${plain}"
    sublink=`cat "${CLASH_DIR}/.sublink"`
   	echo -e "${green}订阅地址：$sublink${plain}"
  	while true; do
    	if ! [[ $sublink =~ ^https?:// ]]; then
    		read -p "请输入您的 Clash 订阅链接，订阅地址请去官网教程复制(不输入内容则默认退出)：" sublink

    		# 检查输入是否是有效的网址并包含 "clash"
    		if [[ $sublink =~ ^https?:// ]]; then
      			break  # 输入有效，跳出循环
    		elif [[ -z $sublink ]]; then
      			exit 1 # 退出脚本，返回非零状态码
    		else
      			echo "输入无效，请重新输入。"
    		fi
		else
			break  # 有效，跳出循环
    	fi
  	done
   apt --version > /dev/null 2>&1
   [ $? -eq 0 ] && tool="apt" 
   yum --version > /dev/null 2>&1
   [ $? -eq 0 ] && tool="yum"
   [ ! -n "$tool" ] && exit 1
   sudo $tool install -y gzip wget
   sudo mkdir -p "${CLASH_DIR}"
   sudo touch "${CLASH_DIR}/.sublink"
   sudo chmod 666 "${CLASH_DIR}/.sublink"
}

install_clash () {
	downloadlink=$(cat "${CLASH_DIR}/.downloadlink")
    read -p "请选择您的处理器架构：1.amd64（默认） 2.arm64。如果是arm64，请输入2，如果您不确定，按下回车键就可以，程序将默认选择1：" cpu
    if [[ $cpu == 2 ]]; then
		URL="$downloadlink/app-download/AppForLinuxArm64.gz"
    else
		URL="$downloadlink/app-download/AppForLinux.gz"
    fi
   	sudo wget --no-check-certificate -O "${CLASH_BIN}.gz" $URL
   	if [[ $? -ne 0 ]]; then
       echo -e "${red}下载 clash 失败，请检查您的网络状况，或稍后再试${plain}"
       exit 1
   	fi
  	sudo rm -rf "${CLASH_BIN}"
  	sudo gzip -d "${CLASH_BIN}.gz"
  	sudo chmod +x "${CLASH_BIN}"
}

download_mmdb () {
	downloadlink=$(cat "${CLASH_DIR}/.downloadlink")
	URL="$downloadlink/app-download/Country.mmdb"
   	sudo wget -O "${CLASH_DIR}/Country.mmdb" $URL
}

import_sublink () {
    sudo wget -O "${CLASH_DIR}/config.yaml" "$sublink" > /dev/null 2>&1
	sudo sh -c "echo \"\$(date +%s)\" > ${CLASH_DIR}/.last_update_script"
    sudo sh -c "echo \"\$(date +%s)\" > ${CLASH_DIR}/.last_update_node"
    echo -e "${green}订阅导入成功！${plain}"
	setup_autostart
	if is_container; then
		set_clash_run_state on
		echo -e "${yellow}容器模式：已写入 /etc/profile.d/clash-autostart.sh（新开 shell 时按 .run_state 决定是否启动）${plain}"
	fi
}

update_sublink () {
    local auto="$1"  # 将参数作为选择

	if [[ ! -n $auto ]]; then
		echo -e "正在更新节点..."
	elif [ -f "${CLASH_DIR}/.last_update_node" ] && (( $(date +%s) - $(cat "${CLASH_DIR}/.last_update_node") < 2592000 )); then                                              
		return                                                         
	fi
                                                      
    sublink=`cat "${CLASH_DIR}/.sublink"`
    if [ ! -n $sublink ]; then 
        res="${red}订阅链接不存在，请重新导入订阅链接!${plain}" 
        exit 1
    fi 

    # 设置超时时间为5秒
    sudo wget --timeout=5 -O "${CLASH_DIR}/temp_config.yaml" "$sublink" > /dev/null 2>&1

    if [ -s "${CLASH_DIR}/temp_config.yaml" ]; then
      	status_rule		# 获取用户之前选择的全局/规则模式
		chosen_node	 	# 获取用户之前选择的节点
      
        sudo mv "${CLASH_DIR}/temp_config.yaml" "${CLASH_DIR}/config.yaml"
      
    	# 如果是全局模式 更新订阅后 切换回用户之前选择的全局模式
		if [[ $status_rule == *"全局"* ]]; then
    		switch_global > /dev/null 2>&1
		fi
		switch_node "$content" "1" > /dev/null 2>&1		 # 更新订阅后，切换回用户之前选择的节点
      
      	sudo sh -c "echo \"\$(date +%s)\" > ${CLASH_DIR}/.last_update_node"
        res="${green}更新节点成功！${plain}"
    else
        res="${red}更新节点失败，请重试！如果一直失败，请去官网复制订阅连接，然后输入11修改订阅链接！${plain}"
    fi
}

modify_sublink () {
	while true; do
    	echo -e "${green}请到官网复制您的订阅地址，并粘贴到此处${plain}"
    	read -p "输入您最新的订阅链接： " sublink
    	# 检查输入是否是有效的网址并包含 "clash"
    	if [[ $sublink =~ ^https?:// ]]; then
      		break  # 输入有效，跳出循环
    	elif [[ -z $sublink ]]; then
      		exit 1 # 退出脚本，返回非零状态码
    	else
      		echo "输入无效，请重新输入。"
    	fi
  	done
    sudo wget -O "${CLASH_DIR}/config.yaml" "$sublink" > /dev/null 2>&1
    sudo echo "$sublink" > "${CLASH_DIR}/.sublink"
	restart_clash
    res="${green}订阅链接修改成功！${plain}"
}

run_clash () {
    set_clash_run_state on
    setsid "${CLASH_BIN}" -d "${CLASH_DIR}" >> /dev/null 2>&1 &
    ps -ef | grep "clash -d" | grep -v grep >> /dev/null 2>&1
    if [ $? -eq 0 ]; then
        res="${green}clash启动成功！${plain}"
    else
        res="${red}启动失败！${plain}"
    	if [ -e "${CLASH_BIN}" ]; then
        	res+="${red}您可尝试更新节点后再启动或联系客服！${plain}"$'\n'
    	else
        	res+="${red}clash 未安装！${plain}"$'\n'
    	fi
    fi
}

status_clash () {
    status_clash="${red}未运行${plain}"
    clash_info=`ps -ef | grep "clash -d" | grep -v grep`
    if [ $? -eq 0 ]; then
        status_clash="${green}运行中${plain}"
    fi
}

stop_clash () {
    set_clash_run_state off
    clash_info=$(ps -ef | grep "clash -d" | grep -v grep)
    if [ $? -eq 0 ]; then
        pkill -f "${CLASH_BIN}"
    fi
    res="${green}停止成功！退出容器后仍保持停止（xcjs 选「运行」可再开）${plain}"
}

restart_clash () {
    set_clash_run_state on
    clash_info=$(ps -ef | grep "clash -d" | grep -v grep)
    if [ $? -eq 0 ]; then
        pkill -f "${CLASH_BIN}"
    fi
    setsid "${CLASH_BIN}" -d "${CLASH_DIR}" >> /dev/null 2>&1 &
    ps -ef | grep "clash -d" | grep -v grep > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        res="${green}重启成功！${plain}"$'\n'
    else
        res="${red}重启失败！${plain}"$'\n'
    fi
}

switch_node() {
	config_file="${CLASH_DIR}/config.yaml"
      
	# 使用sudo sed 命令查找匹配的行，并将内容按行分割成数组
	if grep -q "微软服务" "$config_file"; then
      	# 新的分组有图标
		mapfile -t lines < <(sudo sed -n '/proxy-groups:/,/- name: Ⓜ️ 微软服务/{/^\s\{6\}-/p}' "$config_file")
	elif grep -q "苹果" "$config_file"; then
      	# 新的分组有图标
		mapfile -t lines < <(sudo sed -n '/proxy-groups:/,/- name: 🍎 苹果/{/^\s\{6\}-/p}' "$config_file")
	else
      	# 兼容旧的无图标分组
		mapfile -t lines < <(sudo sed -n '/proxy-groups:/,/- name: Apple/{/^\s\{6\}-/p}' "$config_file")
	fi
      
	# 声明一个数组
	declare -a nodes

	# 输出匹配的内容数组，截取后面的内容并输出
	for i in "${!lines[@]}"; do
		line="${lines[$i]}"
		content="${line#*- }"  # 截取后面的内容
		nodes[$i]="${content:3}"  # 从第4位开始截取到末尾
		echo "$((i+1)). ${nodes[$i]}"
	done

    # 使用传递的参数作为选择
    local node="$1"  # 将参数作为选择

	if [[ ! -n $node ]]; then
		# 询问用户选择哪个节点
		chosen_node
		echo -e ""
		echo -e "您当前选择的节点是${green}${chosen_node}${plain}，请选择新的节点："
		read choice

		# 验证用户输入
		while [[ -z $choice || ! $choice =~ ^[0-9]+$ || $choice -lt 1 || $choice -gt ${#nodes[@]} ]]; do
			if [[ -z $choice ]]; then
				res="您没有选择节点，${green}取消切换。${plain}"
				choice=-1
				break
			else
				if [[ ! $choice =~ ^[0-9]+$ ]]; then
					echo -e "${red}输入的不是有效的数字，请重新输入：${plain}"
				else
					echo -e "${red}输入超出范围，请重新输入：${plain}"
				fi
			fi
			read choice
		done
	fi

	# 获取节点名字
	if [[ ! -n $node ]]; then
    	selected_node_content="${lines[choice-1]}"
	else
		if grep -q -F "$node" "$config_file"; then
    		selected_node_content="$node"
		else
			choice=-1
		fi
	fi

	# 切换节点
	if [[ $choice != -1 ]]; then
		# 删除selected_node_content
		escaped_string=$(printf '%s\n' "$selected_node_content" | sudo sed -e 's/[]\/$*.^[]/\\&/g')
		sudo sed -i "/$escaped_string/d" "$config_file"

		# 在"proxy-groups:"行的下面第4行插入selected_node_content，并保留空格
		sudo sed -i "/proxy-groups:/{n;n;n; r /dev/stdin
		}" "$config_file" <<< "$selected_node_content"
    	# 使用传递的参数作为选择
    	local is_restart="$2"  # 将参数作为选择
        if [[ ! -n $is_restart ]]; then
			restart_clash
        fi
		res="您选择的节点是：${green}$choice. ${nodes[choice-1]}${plain}，已经为您切换到该节点！"
    fi
}

status_rule() {
	config_file="${CLASH_DIR}/config.yaml"
    # 查找是否包含
    if grep -q "\- MATCH,\*,🚀 默认节点" "$config_file"; then
        status_rule="${red}全局代理${plain}"
    else
        status_rule="${green}规则代理${plain}"
    fi
}

chosen_node() {
	config_file="${CLASH_DIR}/config.yaml"

	# 使用grep命令查找"    proxies:"的行号
	line_number=$(grep -n "    proxies:" "$config_file" | cut -d ':' -f 1 | head -n 1)

	# 如果找到了匹配的行，则获取下一行的内容并输出
	if [ -n "$line_number" ]; then
		line_number=$((line_number + 1))
		content=$(sudo sed -n "${line_number}p" "$config_file")
		chosen_node="${content#*- }"  # 截取后面的内容
		chosen_node="${chosen_node:3}"  # 截取后面的内容
		chosen_node="${green}${chosen_node}${plain}"  # 从第4位开始截取到末尾
	else
		chosen_node="${red}无法显示，请尝试更新节点！${plain}"
	fi
}

switch_rule() {
	config_file="${CLASH_DIR}/config.yaml"
    # 查找是否包含
    if grep -q "\- MATCH,\*,🚀 默认节点" "$config_file"; then
        echo -e "当前模式为 ${red}全局代理${plain}，正在切换..."
        # 如果包含，删除 config_file 中包含的行
        sudo sed -i '/- MATCH,\*,🚀 默认节点/d' "$config_file"
		restart_clash
        res+="已经切换为 ${green}规则代理${plain} ！"$'\n'
    else
        res="当前模式为 ${green}规则代理${plain}，无需切换"$'\n'
    fi
}

switch_global () {
	config_file="${CLASH_DIR}/config.yaml"
    # 查找是否包含
    if grep -q "\- MATCH,\*,🚀 默认节点" "$config_file"; then
        res="当前模式为 ${red}全局代理${plain}，无需切换"$'\n'
    else
        echo -e "当前模式为 ${green}规则代理${plain}，正在切换到 ${red}全局代理${plain}..."
        # 如果不包含，在包含rules:的这一行下面插入
        sudo sed -i '/^rules:/a\  - MATCH,\*,🚀 默认节点' "$config_file"
		restart_clash
        res+="已经切换为 ${red}全局代理${plain}！"$'\n'
    fi
}

uninstall_clash () {
    if [ -e "${CLASH_BIN}" ]; then
        stop_clash > /dev/null 2>&1
        remove_autostart
        sudo rm -rf "${CLASH_BIN}"
        sudo rm -rf "${CLASH_DIR}/config.yaml"
        sudo rm -rf "${CLASH_DIR}/Country.mmdb"
        sudo rm -f "${CLASH_RUN_STATE}"
        res="${red}卸载 Clash 成功！${plain}"
    else
        res="${red}Clash 未安装，无需卸载！${plain}"
    fi
}

uninstall_script () {
    if [ -d "${CLASH_DIR}" ]; then
        remove_autostart
        sudo rm -rf "${CLASH_DIR}"
        res="${red}卸载脚本成功！${plain}"
    else
        res="${red}目录 ${CLASH_DIR} 不存在，无需卸载脚本！${plain}"
    fi
}

_print_official_proxy_exports() {
    local host="${1:-127.0.0.1}"
    local http_proxy_val="http://${host}:${CLASH_PORT}"
    local socks_proxy_val="socks5://${host}:${CLASH_PORT}"
    local no_proxy_val="localhost,127.0.0.0/8,::1"
    echo -e "${red}export http_proxy=${http_proxy_val}${plain}"
    echo -e "${red}export https_proxy=${http_proxy_val}${plain}"
    echo -e "${red}export HTTP_PROXY=${http_proxy_val}${plain}"
    echo -e "${red}export HTTPS_PROXY=${http_proxy_val}${plain}"
    echo -e "${red}export socks_proxy=${socks_proxy_val}${plain}"
    echo -e "${red}export SOCKS_PROXY=${socks_proxy_val}${plain}"
    echo -e "${red}export no_proxy=${no_proxy_val}${plain}"
    echo -e "${red}export NO_PROXY=${no_proxy_val}${plain}"
    echo -e "${red}unset ftp_proxy FTP_PROXY${plain}"
}

_print_official_proxy_unsets() {
    echo -e "${red}unset http_proxy https_proxy ftp_proxy socks_proxy${plain}"
    echo -e "${red}unset HTTP_PROXY HTTPS_PROXY FTP_PROXY SOCKS_PROXY${plain}"
    echo -e "${red}unset no_proxy NO_PROXY${plain}"
}

terminal_proxy () {
    while true; do
    	echo -e "${green}1.开启命令行代理（临时）${plain}"
    	echo -e "${green}2.开启命令行代理（永久）${plain}"
    	read -p "请输入您的选择： " choice
    	if [[ $choice == "1" ]]; then
    		echo -e "${green}您选择的是：1.开启命令行代理（临时）${plain}"
    		echo -e "${green}请复制下面的代码，在终端执行命令（与官网一致，FTP 关闭）：${plain}"
    		_print_official_proxy_exports "127.0.0.1"
    		if is_container; then
    			echo -e "${yellow}容器内建议直接执行 proxy_on（已按官网参数配置）${plain}"
    		fi
      		exit 0
    	elif [[ $choice == "2" ]]; then 
    		echo -e "${green}您选择的是：2.开启命令行代理（永久）${plain}"
    		if is_container && declare -f proxy_on >/dev/null 2>&1; then
    			proxy_on
    			res="${green}已通过 proxy_on 开启（与官网一致）${plain}"
    		elif ! grep -q 'proxy_on()' ~/.bashrc 2>/dev/null; then
    			{
    				echo "export http_proxy=http://127.0.0.1:${CLASH_PORT}"
    				echo "export https_proxy=http://127.0.0.1:${CLASH_PORT}"
    				echo "export HTTP_PROXY=http://127.0.0.1:${CLASH_PORT}"
    				echo "export HTTPS_PROXY=http://127.0.0.1:${CLASH_PORT}"
    				echo "export socks_proxy=socks5://127.0.0.1:${CLASH_PORT}"
    				echo "export SOCKS_PROXY=socks5://127.0.0.1:${CLASH_PORT}"
    				echo "export no_proxy=localhost,127.0.0.0/8,::1"
    				echo "export NO_PROXY=localhost,127.0.0.0/8,::1"
    				echo "unset ftp_proxy FTP_PROXY"
    			} >> ~/.bashrc
    			source ~/.bashrc 2>/dev/null || true
    			res="${green}永久命令行代理开启成功！${red}需要重启终端命令窗口生效！${plain}"
    		else
    			proxy_on 2>/dev/null || source ~/.bashrc 2>/dev/null || true
    			res="${green}永久命令行代理开启成功！${red}需要重启终端命令窗口生效！${plain}"
    		fi
			if is_container && grep -q 'proxy_on()' ~/.bashrc 2>/dev/null; then
				res+="${yellow} 提示：日常建议直接执行 proxy_on。${plain}"
			fi
      		break
   	 	else
      		echo -e "输入无效，请重新输入"
    	fi
    done
}

unset_terminal_proxy () {
    while true; do
    	echo -e "${green}1.关闭命令行代理（临时）${plain}"
    	echo -e "${green}2.关闭命令行代理（永久）${plain}"
    	read -p "请输入您的选择： " choice
    	if [[ $choice == "1" ]]; then
    		echo -e "${green}您选择的是：1.关闭命令行代理（临时）${plain}"
    		echo -e "${green}请复制下面的代码，在终端执行命令：${plain}"
    		_print_official_proxy_unsets
    		if is_container; then
    			echo -e "${yellow}容器内也可执行 proxy_off${plain}"
    		fi
      		exit 0
    	elif [[ $choice == "2" ]]; then 
    		echo -e "${green}您选择的是：2.关闭命令行代理（永久）${plain}"
    		if is_container && declare -f proxy_off >/dev/null 2>&1; then
    			proxy_off
    			res="${green}已通过 proxy_off 关闭${plain}"
    		else
				{
					echo "unset http_proxy https_proxy ftp_proxy socks_proxy"
					echo "unset HTTP_PROXY HTTPS_PROXY FTP_PROXY SOCKS_PROXY"
					echo "unset no_proxy NO_PROXY"
				} >> ~/.bashrc
    			source ~/.bashrc
    			res="${green}永久命令行代理关闭成功！${red}需要重启终端命令窗口生效！${plain}"
    		fi
      		break
   	 	else
      		echo -e "输入无效，请重新输入"
    	fi
    done
}
      
# 容器内刷新 profile.d 自启脚本（含 .run_state 逻辑）
if is_container && [ -x "${CLASH_BIN}" ]; then
    setup_autostart >/dev/null 2>&1
fi

if [ $# -gt 0 ]; then
    case $1 in
	"update_sublink")
        update_sublink
        restart_clash
	exit 0
	;;
        *)
        ;;
    esac
fi

while true
do

clear
echo "Clash 操作台"
if is_container; then
	echo -e "${yellow}[容器模式] Clash: ${CLASH_RUN_STATE} | 终端代理: /workspace/.proxy_state | proxy_on / proxy_off${plain}"
fi
echo "================安装================"
echo "1、安装软件"
echo "=============启动/停止=============="
echo "2、运行软件"
echo "3、停止软件"
echo "4、重启软件"
echo "================节点================"
echo "5、切换节点"
echo "6、更新节点"
echo "================其他================"
echo "7、切换到规则模式(默认 智能区分流量)"
echo "8、切换到全局模式(所有流量走代理)"
echo "9、开启命令行代理"
echo "10、关闭命令行代理"
echo "11、修改订阅链接"
echo "12、检测/升级本脚本"
echo "================卸载================"
echo "13、卸载clash"
echo "14、卸载本脚本"
echo "================退出================"
echo -e "0、退出脚本（在终端输入${green}“xcjs”${plain}即可快速打开脚本）"
echo "===================================="
if [ -e "${CLASH_BIN}" ] && [ -d "${CLASH_DIR}" ]; then
	status_clash
	echo -e "运行状态：$status_clash"
	status_rule
	echo -e "代理模式：$status_rule"
	chosen_node
	echo -e "当前节点：$chosen_node"
	echo "===================================="
	update_sublink "1" > /dev/null 2>&1
	update_script "1" "$1"
fi
echo ""
echo -e "$res"
read -p "请选择您要的操作: " choise_num
case $choise_num in
    0)
    exit 0
    ;;
    1)
    pre_setup
    install_clash
    download_mmdb
    import_sublink
    echo -e "${green}重启终端后，输入${red} xcjs ${green}即可快速打开脚本${plain}"
    if is_container; then
    	echo -e "${green}容器内：停止后 exit 再进不会自动拉起；终端代理请用 ${red}proxy_on${green} / ${red}proxy_off${plain}"
    fi
    echo -e "${green}安装成功！clash可以开始运行${plain}"
    read -p "回车退出 "
    continue
    ;;
    2)
    run_clash
    continue
    ;;
    3)
    stop_clash   
    continue
    ;;
    4)
    restart_clash
    continue
    ;;
    5)
    switch_node
    continue
    ;;
    6)
    update_sublink
    continue
    ;;
    7)
    switch_rule
    continue
    ;;
    8)
    switch_global
    continue
    ;;
    9)
	terminal_proxy
    continue
    ;;
    10)
	unset_terminal_proxy
    continue
    ;;
    11)
    modify_sublink
    continue
    ;;
    12)
    update_script
    continue
    ;;
    13)
    uninstall_clash
    continue
    ;;
    14)
    uninstall_script
    continue
    ;;
    *)
    exit 1
    ;;
esac
done