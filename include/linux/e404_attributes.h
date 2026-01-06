#ifndef _E404_ATTRIBUTES_H
#define _E404_ATTRIBUTES_H

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>

struct e404_attributes {
    int kgsl_skip_zeroing;
    int file_sync;
    int avoid_dirty_pte;
};

extern struct e404_attributes e404_data;

#endif /* _E404_ATTRIBUTES_H */
