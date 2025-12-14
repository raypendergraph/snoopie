// Native Zig definitions for Bluetooth C library
// Avoids @cImport issues with complex macros in bluetooth headers

const std = @import("std");

// Bluetooth address structure
pub const bdaddr_t = extern struct {
    b: [6]u8,
};

// HCI device info structure
pub const hci_dev_info = extern struct {
    dev_id: u16,
    name: [8]u8,
    bdaddr: bdaddr_t,
    flags: u32,
    type: u8,
    features: [8]u8,
    pkt_type: u32,
    link_policy: u32,
    link_mode: u32,
    acl_mtu: u16,
    acl_pkts: u16,
    sco_mtu: u16,
    sco_pkts: u16,
    stat: extern struct {
        err_rx: u32,
        err_tx: u32,
        cmd_tx: u32,
        evt_rx: u32,
        acl_tx: u32,
        acl_rx: u32,
        sco_tx: u32,
        sco_rx: u32,
        byte_rx: u32,
        byte_tx: u32,
    },
};

// Inquiry info structure for device scanning
pub const inquiry_info = extern struct {
    bdaddr: bdaddr_t,
    pscan_rep_mode: u8,
    pscan_period_mode: u8,
    pscan_mode: u8,
    dev_class: [3]u8,
    clock_offset: u16,
};

// Constants
pub const IREQ_CACHE_FLUSH = 0x0001;
pub const HCI_MAX_DEV = 16;
pub const BDADDR_ANY = bdaddr_t{ .b = [_]u8{ 0, 0, 0, 0, 0, 0 } };

// External C functions from libbluetooth
extern "c" fn hci_get_route(bdaddr: ?*const bdaddr_t) c_int;
extern "c" fn hci_open_dev(dev_id: c_int) c_int;
extern "c" fn hci_close_dev(dd: c_int) c_int;
extern "c" fn hci_devlist(nr: c_int, dl: *anyopaque) c_int;
extern "c" fn hci_devinfo(dev_id: c_int, di: *hci_dev_info) c_int;
extern "c" fn hci_inquiry(dev_id: c_int, len: c_int, num_rsp: c_int, lap: ?*const u8, ii: [*c]*inquiry_info, flags: c_long) c_int;
extern "c" fn hci_read_remote_name(dd: c_int, bdaddr: *const bdaddr_t, len: c_int, name: [*c]u8, timeout: c_int) c_int;
extern "c" fn ba2str(ba: *const bdaddr_t, str: [*c]u8) c_int;
extern "c" fn str2ba(str: [*c]const u8, ba: *bdaddr_t) c_int;

// Wrapper functions with better Zig types
pub fn getRoute(bdaddr: ?*const bdaddr_t) !c_int {
    const dev_id = hci_get_route(bdaddr);
    if (dev_id < 0) {
        return error.NoBluetoothDevice;
    }
    return dev_id;
}

pub fn openDevice(dev_id: c_int) !c_int {
    const dd = hci_open_dev(dev_id);
    if (dd < 0) {
        return error.CannotOpenDevice;
    }
    return dd;
}

pub fn closeDevice(dd: c_int) void {
    _ = hci_close_dev(dd);
}

pub fn getDeviceInfo(dev_id: c_int) !hci_dev_info {
    var info: hci_dev_info = undefined;
    const result = hci_devinfo(dev_id, &info);
    if (result < 0) {
        return error.CannotGetDeviceInfo;
    }
    return info;
}

pub fn inquiry(dev_id: c_int, len: c_int, max_devices: c_int, flags: c_long) !struct { info: [*c]*inquiry_info, count: c_int } {
    var ii: [*c]*inquiry_info = null;
    const num_rsp = hci_inquiry(dev_id, len, max_devices, null, &ii, flags);
    if (num_rsp < 0) {
        return error.InquiryFailed;
    }
    return .{ .info = ii, .count = num_rsp };
}

pub fn readRemoteName(dd: c_int, bdaddr: *const bdaddr_t, timeout: c_int) ![248]u8 {
    var name: [248]u8 = undefined;
    const result = hci_read_remote_name(dd, bdaddr, 248, &name, timeout);
    if (result < 0) {
        return error.CannotReadName;
    }
    return name;
}

pub fn addrToString(bdaddr: *const bdaddr_t) ![18]u8 {
    var str: [18]u8 = undefined;
    const result = ba2str(bdaddr, &str);
    if (result < 0) {
        return error.InvalidAddress;
    }
    return str;
}

pub fn stringToAddr(str: [*c]const u8) !bdaddr_t {
    var bdaddr: bdaddr_t = undefined;
    const result = str2ba(str, &bdaddr);
    if (result < 0) {
        return error.InvalidAddressString;
    }
    return bdaddr;
}
