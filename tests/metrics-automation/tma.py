#!/usr/bin/python3

# pip3 install pyzabbix
import sys, argparse, re
from pyzabbix import ZabbixAPI, ZabbixAPIException
# disabling https warnings beacuse the internal IP address is used
# and the certificate of public IP won't match then and it will raise an error
import urllib3
urllib3.disable_warnings()
from datetime import datetime

#ZUSER = "__CHANGEZUSER__"
#ZPASSWORD = "__CHANGEZPASSWORD__"
#ZTOKEN = "__CHANGEZTOKEN__"
ZSERVER = "127.0.0.1"
ZURL = f"https://{ZSERVER}"
ZTIMEOUT = 5.0

def main():
    ap = argparse.ArgumentParser(prog="TMA, Test Metrics Automation",
                                description="Tool to add hosts and items for test automation to Zabbix server.")
    ap.add_argument("-n", "--host-name", dest="hostname_name",
                    help="Mandatory. Name of the host in Zabbix.")
    ap.add_argument("-i", "--item-name", dest="hostname_item_name",
                    help="Mandatory. Name of the item/metric.")
    ap.add_argument("-j", "--item-type", choices=[0,1,2,3,4], default=0, type=int, dest="hostname_item_value_type",
                    help="0 - float (default), 1 - char, 2 - log, 3 - unsigned int, 4 - text.")
    ap.add_argument("-k", "--keep-history", default="365d", dest="hostname_item_history",
                    help="Keep history for N hours/days, like: 8h, 14d, .... Default vslue is 365d.")
    ap.add_argument("-t", "--keep-trends", default="365d", dest="hostname_item_trends",
                    help="Keep trends for N hours/days, like: 8h, 14d, .... Default value is 365d.")
    ap.add_argument("-u", "--units", dest="hostname_item_units",
                    help="Units, shown in graphs.")
    ap.add_argument("-v", "--verbose", action="store_true", dest="verbosity",
                    help="Verbosity.")
    ap.add_argument("-d", "--dry-run", action="store_true", dest="dryrun",
                    help="Dry run. Do all necessary checks including server connection and finish. No item will be created.")
    args = ap.parse_args()
   
    # parameters check
    if not args.hostname_name or \
       not args.hostname_item_name or \
       not re.match("^[0-9]+[dh]{1}$", args.hostname_item_history) or \
       not re.match("^[0-9]+[dh]{1}$", args.hostname_item_history):
        ap.print_help()
        sys.exit(1)
    zobj = ZabbixAPI(server=ZURL, detect_version=False, timeout=ZTIMEOUT)
    # disabling session verification because of the server certificate bind to a public IP
    zobj.session.verify = False
    if "ZUSER" in globals() and "ZPASSWORD" in globals():
        if args.verbosity:
            print("[INFO] Using user and password authentication.")
        zobj.login(ZUSER, ZPASSWORD)
    elif "ZTOKEN" in globals():
        if args.verbosity:
            print("[INFO] Using token authentication.")
        zobj.login(api_token=ZTOKEN)
    else:
        print("No credentials set. Cannot authenticate against Zabbix server. Quitting...")
        sys.exit(1)
    try:
        zobj.api_version()
        if args.verbosity:
            print("[INFO] Connection established successfuly.")
    except:
        print("[ERROR] Connection not established.")
        sys.exit(1)
    if args.dryrun:
        print("Dry run, finishing here.")
        sys.exit(0)
    host = []
    host = zobj.host.get(filter={"host": args.hostname_name})
    if not host:
        hostgroup = zobj.hostgroup.get(filter={"name": "Applications"})
        try:
            zobj.host.create(host=args.hostname_name, groups={"groupid": hostgroup[0]["groupid"]})
            host = zobj.host.get(filter={"host": args.hostname_name})
        except ZabbixAPIException as e:
            print(e)
            sys.exit(1)
    print(f"[INFO] Hostname '{args.hostname_name}' with item ID: {host[0]['hostid']} created.")
    item = []
    item = zobj.item.get(hostids=host[0]['hostid'], filter={"name": args.hostname_item_name}, output=("itemid",))
    # finish if the item already exists
    if item:
        print(f"Item '{args.hostname_item_name}' already exists with ID: {item[0]['itemid']}! Quitting...")
        sys.exit(1)
    try:
        # type=2 is the "TRAP" type in Zabbix
        item = zobj.item.create(
            hostid=host[0]["hostid"],
            name=args.hostname_item_name,
            key_=args.hostname_item_name,
            type=2,
            value_type=args.hostname_item_value_type,
            history=args.hostname_item_history,
            trends=args.hostname_item_trends,
            units=args.hostname_item_units
        )
        print(f"[INFO] Item '{args.hostname_item_name}' with item ID {item['itemids'][0]} added to host: {args.hostname_name}")
    except ZabbixAPIException as e:
        print(e)


if __name__ == "__main__":
    main()
