# python 3.12
# Return a list of mountable labeled external partitions (one label per line)

from diskinfo import DiskInfo

di = DiskInfo()
disks = di.get_disk_list(sorting=True)

for d in disks:
    if d.get_partition_table_type() == "":
        continue
    for item in d.get_partition_list():
        label = item.get_fs_label()
        if not label:
            continue
        if label.startswith("hassos"):
            continue
        print(label)
