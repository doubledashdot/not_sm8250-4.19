// E404 Manager by Project 113 (kvsnr113)

#include <linux/e404_attributes.h>

struct e404_attributes e404_data = {
    .e404_kgsl_skip_zeroing = 0,
};

static struct kobject *e404_kobj;

#define E404_ATTR_RO(name) \
static ssize_t name##_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) { \
    return sprintf(buf, "%d\n", e404_data.name); \
} \
static struct kobj_attribute name##_attr = __ATTR(name, 0444, name##_show, NULL);

#define E404_ATTR_RW(name) \
static ssize_t name##_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) { \
    return sprintf(buf, "%d\n", e404_data.name); \
} \
static ssize_t name##_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) { \
    int ret, val, old_val; \
    ret = kstrtoint(buf, 10, &val); \
    if (ret) return ret; \
    old_val = e404_data.name; \
    e404_data.name = val; \
    pr_alert("E404: %s changed from %d to %d\n", #name, old_val, val); \
    sysfs_notify(e404_kobj, NULL, #name); \
    return count; \
} \
static struct kobj_attribute name##_attr = __ATTR(name, 0664, name##_show, name##_store);

E404_ATTR_RW(e404_kgsl_skip_zeroing);

static struct attribute *e404_attrs[] = {
    &e404_kgsl_skip_zeroing_attr.attr,
    NULL,
};

static struct attribute_group e404_attr_group = {
    .attrs = e404_attrs,
};

static int __init e404_init(void) {
    int ret;

    e404_kobj = kobject_create_and_add("e404", kernel_kobj);
    if (!e404_kobj)
        return -ENOMEM;

    ret = sysfs_create_group(e404_kobj, &e404_attr_group);
    if (ret)
        kobject_put(e404_kobj);

    pr_alert("E404: Kernel Module & Sysfs Initialized\n");

    return ret;
}

static void __exit e404_exit(void) {
    kobject_put(e404_kobj);
    pr_alert("E404: Kernel Module & Sysfs Removed\n");
}

core_initcall(e404_init);
module_exit(e404_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("kvsnr113");
MODULE_DESCRIPTION("E404 manager via early_param and sysfs");
MODULE_VERSION("1.3");
