"""
用crontab每天自动切换站点
20 14 * * * curl -s https://raw.githubusercontent.com/doKill/some-py-codes/master/autoChangHySite.py | python3
"""


from datetime import datetime
import random
import subprocess
import logging
import os
import sys

def check_and_install_yaml():
    """
    检查是否安装 PyYAML 模块。如果未安装，则通过 apt-get 安装。
    """
    try:
        import yaml
    except ImportError:
        print("未检测到 PyYAML 模块，正在尝试通过 apt-get 安装...")
        try:
            subprocess.run(["sudo", "apt-get", "update"], check=True)
            subprocess.run(["sudo", "apt-get", "install", "-y", "python3-yaml"], check=True)
        except subprocess.CalledProcessError as e:
            print(f"通过 apt-get 安装 PyYAML 模块失败，请检查网络连接或权限问题。\n错误详情: {e}")
            sys.exit(1)
        # 安装后重新导入
        try:
            import yaml
        except ImportError:
            print("安装后加载 PyYAML 模块失败，请检查环境配置。")
            sys.exit(1)
    return yaml

# 使用模块
yaml = check_and_install_yaml()

# 定义日志文件路径
LOG_FILE = '/root/hy/auto-change-site.log'
LOG_DIR = os.path.dirname(LOG_FILE)

# 确保日志目录存在
if not os.path.exists(LOG_DIR):
    try:
        os.makedirs(LOG_DIR, mode=0o755)
        subprocess.run(['chown', 'root:root', LOG_DIR], check=True)
    except Exception as e:
        print(f"创建日志目录失败: {e}")
        exit(1)

# 确保日志文件存在并设置权限
if not os.path.exists(LOG_FILE):
    try:
        open(LOG_FILE, 'a').close()  # 创建文件
        subprocess.run(['chown', 'root:root', LOG_FILE], check=True)
        os.chmod(LOG_FILE, 0o644)  # 设置权限为 644
    except Exception as e:
        print(f"创建日志文件失败: {e}")
        exit(1)

# 配置日志
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)


# URL 数组
urls = ['https://harvard.edu','https://stanford.edu','https://mit.edu','https://caltech.edu','https://uchicago.edu','https://princeton.edu','https://columbia.edu','https://yale.edu','https://upenn.edu','https://duke.edu','https://nyu.edu','https://berkeley.edu','https://cornell.edu','https://northwestern.edu','https://umich.edu','https://cmu.edu','https://usc.edu','https://gatech.edu','https://washington.edu','https://ucla.edu','https://www.imdb.com/','https://www.zygotebody.com/','https://javascript.info/','https://www.tesla.com/','https://clippingmagic.com/','https://www.dell.com/en-us/gaming/','https://us.louisvuitton.com/','https://www.prada.com/us','https://www.gucci.com/us','https://www.porsche.com/usa/','https://www.cartier.com/en-us/home','https://www.dior.com/en_us','https://www.rolex.com/en-us','https://ipcheck.ing/']
config_file_path = '/etc/hysteria/config.yaml'

def update_config():
    try:
        # 随机选择一个 URL
        selected_url = random.choice(urls)
        
        # 读取当前配置文件
        with open(config_file_path, 'r') as file:
            config = yaml.safe_load(file)
        
        # 更新 URL
        if 'masquerade' in config and 'proxy' in config['masquerade']:
            config['masquerade']['proxy']['url'] = selected_url

        # 写入更新后的配置文件
        with open(config_file_path, 'w') as file:
            yaml.dump(config, file)

        # 重启服务时传入选中的 URL
        restart_service(selected_url)
    except Exception as e:
        logging.error(f"更新配置时出错: {e}")
        exit(1)

def restart_service(url):
    try:
        # 使用 subprocess 执行 systemctl restart 命令
        subprocess.run(['sudo', 'systemctl', 'restart', 'hysteria-server.service'], check=True)
        logging.info(f"Masquerade URL已更改，当前使用的是: {url}")
        print(f"Masquerade URL已更改，当前使用的是: {url}")
    except subprocess.CalledProcessError as e:
        logging.error(f"重启服务时出错: {e}, 失败时的目标 URL: {url}")

if __name__ == "__main__":
    update_config()
