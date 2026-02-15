"""
用 crontab 每天自动切换 hysteria2 站点，支持地区: us, sg, jp
示例:
20 14 * * * curl -s https://raw.githubusercontent.com/doKill/some-py-codes/master/autoChangHySite.py | python3
"""

from datetime import datetime
import json
import logging
import os
import random
import subprocess
import sys


def merge_unique(*lists):
    """按出现顺序去重并合并多个列表。"""
    seen = set()
    merged = []
    for items in lists:
        for item in items:
            if item not in seen:
                seen.add(item)
                merged.append(item)
    return merged


# 获取服务器所属国家
def get_server_country():
    try:
        result = subprocess.run(['curl', '-s', 'http://ip-api.com/json'], capture_output=True, text=True)
        data = result.stdout
        parsed_data = json.loads(data)
        return parsed_data.get('countryCode', 'US')
    except Exception as e:
        print(f"获取国家代码错误  {e}")
        return "US" # 出错时直接返回 US


gfw_resistant_urls = [
    "https://www.apple.com",
    "https://developer.apple.com",
    "https://raw.githubusercontent.com",
    "https://www.microsoft.com",
    "https://update.microsoft.com",
    "https://azure.microsoft.com",
    "https://aws.amazon.com",
    "https://s3.amazonaws.com",
    "https://d1.awsstatic.com",
    "https://scholar.google.com",
    "https://arxiv.org",
    "https://www.ieee.org",
    "https://www.springer.com",
    "https://www.debian.org",
    "https://download.oracle.com",
    "https://developer.nvidia.com",
]


sg_urls = [
    "https://www.nus.edu.sg",
    "https://www.ntu.edu.sg",
    "https://www.smu.edu.sg",
    "https://www.sutd.edu.sg",
    "https://www.singaporetech.edu.sg",
    "https://www.lasalle.edu.sg",
    "https://www.nafa.edu.sg",
    "https://www.sim.edu.sg",
    "https://www.dimensions.edu.sg",
    "https://www.kaplan.com.sg",
    "https://www.raffles-iao.com",
    "https://www.psb-academy.edu.sg",
    "https://www.singtel.com",
    "https://www.shrm.edu.sg",
    "https://www.lazada.sg",
    "https://shopee.sg",
    "https://www.hardwarezone.com.sg",
    "https://www.straitstimes.com",
    "https://www.channelnewsasia.com",
    "https://www.mom.gov.sg",
    "https://www.imda.gov.sg",
    "https://www.mas.gov.sg",
    "https://www.ica.gov.sg",
    "https://www.nparks.gov.sg",
    "https://www.nea.gov.sg",
    "https://www.changiairport.com",
    "https://www.businesstimes.com.sg",
    "https://www.todayonline.com",
    "https://www.starhub.com",
    "https://www.m1.com.sg",
    "https://www.sgx.com",
    "https://www.ura.gov.sg",
    "https://www.singpost.com",
    "https://www.mediacorp.sg",
    "https://www.lta.gov.sg",
    "https://www.pub.gov.sg",
    "https://www.smrt.com.sg",
]


us_urls = [
    "https://harvard.edu",
    "https://stanford.edu",
    "https://mit.edu",
    "https://caltech.edu",
    "https://uchicago.edu",
    "https://princeton.edu",
    "https://columbia.edu",
    "https://yale.edu",
    "https://upenn.edu",
    "https://duke.edu",
    "https://nyu.edu",
    "https://berkeley.edu",
    "https://cornell.edu",
    "https://northwestern.edu",
    "https://umich.edu",
    "https://cmu.edu",
    "https://usc.edu",
    "https://gatech.edu",
    "https://washington.edu",
    "https://ucla.edu",
    "https://www.imdb.com/",
    "https://www.zygotebody.com/",
    "https://javascript.info/",
    "https://www.tesla.com/",
    "https://clippingmagic.com/",
    "https://www.dell.com/en-us/gaming/",
    "https://us.louisvuitton.com/",
    "https://www.prada.com/us",
    "https://www.gucci.com/us",
    "https://www.porsche.com/usa/",
    "https://www.cartier.com/en-us",
    "https://www.dior.com/en_us",
    "https://www.rolex.com/en-us",
    "https://www.ncbi.nlm.nih.gov/pmc",
    "https://www.jstor.org",
    "https://muse.jhu.edu",
    "https://www.researchgate.net",
    "https://www.academia.edu",
    "https://eric.ed.gov",
    "https://www.ssrn.com",
    "https://www.plos.org",
]


jp_urls = [
    "https://www.u-tokyo.ac.jp",
    "https://www.kyoto-u.ac.jp",
    "https://www.titech.ac.jp",
    "https://www.osaka-u.ac.jp",
    "https://www.tohoku.ac.jp",
    "https://www.nagoya-u.ac.jp",
    "https://www.kyushu-u.ac.jp",
    "https://www.hokudai.ac.jp",
    "https://www.waseda.jp",
    "https://www.keio.ac.jp",
    "https://www.tsukuba.ac.jp",
    "https://www.kobe-u.ac.jp",
    "https://www.hiroshima-u.ac.jp",
    "https://www.hit-u.ac.jp",
    "https://www.ritsumei.ac.jp",
    "https://www.tmd.ac.jp",
    "https://www.tus.ac.jp",
    "https://www.chiba-u.ac.jp",
    "https://www.nagasaki-u.ac.jp",
    "https://www.okayama-u.ac.jp",
]


url_mapping = {
    "sg": merge_unique(sg_urls, gfw_resistant_urls),
    "us": merge_unique(us_urls, gfw_resistant_urls),
    "jp": merge_unique(jp_urls, gfw_resistant_urls),
}


def check_and_install_yaml():
    """
    检查是否安装 PyYAML 模块。如果未安装，尝试通过 apt-get 安装。
    """
    try:
        import yaml
        return yaml
    except ImportError:
        print("未检测到 PyYAML 模块，正在尝试通过 apt-get 安装...")

    apt_prefix = [] if os.geteuid() == 0 else ["sudo"]
    try:
        subprocess.run(apt_prefix + ["apt-get", "update"], check=True)
        subprocess.run(apt_prefix + ["apt-get", "install", "-y", "python3-yaml"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"通过 apt-get 安装 PyYAML 模块失败: {e}")
        sys.exit(1)

    try:
        import yaml
        return yaml
    except ImportError:
        print("安装后加载 PyYAML 模块失败，请检查环境配置。")
        sys.exit(1)


yaml = check_and_install_yaml()

country_code = get_server_country()
urls = url_mapping.get(country_code.lower(), ["https://bing.com"])

LOG_FILE = "/root/hy/auto-change-site.log"
LOG_DIR = os.path.dirname(LOG_FILE)

if not os.path.exists(LOG_DIR):
    try:
        os.makedirs(LOG_DIR, mode=0o755)
        subprocess.run(["chown", "root:root", LOG_DIR], check=True)
    except Exception as e:
        print(f"创建日志目录失败: {e}")
        sys.exit(1)

if not os.path.exists(LOG_FILE):
    try:
        open(LOG_FILE, "a").close()
        subprocess.run(["chown", "root:root", LOG_FILE], check=True)
        os.chmod(LOG_FILE, 0o644)
    except Exception as e:
        print(f"创建日志文件失败: {e}")
        sys.exit(1)

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)


def restart_service(url):
    try:
        cmd = ["systemctl", "restart", "hysteria-server.service"]
        if os.geteuid() != 0:
            cmd.insert(0, "sudo")
        subprocess.run(cmd, check=True)
        logging.info(f"Masquerade URL 已更改，当前使用: {url}")
        print(f"Masquerade URL 已更改，当前使用: {url}")
    except subprocess.CalledProcessError as e:
        logging.error(f"重启服务时出错: {e}, 失败目标 URL: {url}")


def update_config():
    config_file_path = "/etc/hysteria/config.yaml"
    try:
        selected_url = random.choice(urls)

        with open(config_file_path, "r", encoding="utf-8") as file:
            config = yaml.safe_load(file) or {}

        if not isinstance(config, dict):
            raise ValueError("配置文件结构异常，根节点不是对象")

        config.setdefault("masquerade", {})
        config["masquerade"].setdefault("proxy", {})
        config["masquerade"]["proxy"]["url"] = selected_url

        with open(config_file_path, "w", encoding="utf-8") as file:
            yaml.safe_dump(config, file, sort_keys=False, allow_unicode=True)

        restart_service(selected_url)
    except Exception as e:
        logging.error(f"更新配置时出错: {e}")
        sys.exit(1)


if __name__ == "__main__":
    logging.info(f"任务开始，时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}，地区: {country_code}")
    update_config()
