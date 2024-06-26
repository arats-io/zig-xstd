const std = @import("std");
const Buffer = @import("../../bytes/buffer.zig");

const ints = @import("../../ints.zig");

pub const ExtraFieldHeaderID = enum(u16) {
    Zip64ExtendedInfo = 0x0001,
    AVInfo = 0x0007,
    Reserved01 = 0x0008,
    OS2ExtendedAttributes = 0x0009,
    NTFS = 0x000a,
    OpenVMS = 0x000c,
    UNIX = 0x000d,
    Reserved02 = 0x000e,
    PatchDescriptor = 0x000f,
    StoreForX509Certificates = 0x0014,
    X509CertificateIDAndSignatureForFile = 0x0015,
    X509CertificateIDForCentralDirectory = 0x0016,
    StrongEncryption = 0x0017,
    RecordManagementControls = 0x0018,
    EncryptionRecipientCertificateList = 0x0019,
    ReservedForTimestampRecord = 0x0020,
    PolicyDecryptionKeyRecord = 0x0021,
    SmartcryptKeyProviderRecord = 0x0022,
    SmartcryptPolicyKeyDataRecord = 0x0023,
    IBMSZ390AS400I400Attributes = 0x0065,
    ReservedIBMSZ390AS400I400Attributes = 0x0066,
    POSZIP4690 = 0x4690,
    InfoZIPMacintoshOld = 0x07c8,
    PixarUSD = 0x1986,
    ZipItMacintoshV1 = 0x2605,
    ZipItMacintoshV135 = 0x2705,
    ZipItMacintoshV135Plus = 0x2805,
    InfoZIPMacintoshNew = 0x334d,
    TandemNSK = 0x4154,
    AcornSparkFS = 0x4341,
    WindowsNTSecurityDescriptor = 0x4453,
    VMCMS = 0x4704,
    MVS = 0x470f,
    TheosOld = 0x4854,
    FWKCSMD5 = 0x4b46,
    OS2ACL = 0x4c41,
    InfoZIPOpenVMS = 0x4d49,
    MacintoshSmartZIP = 0x4d63,
    XceedOriginalLocation = 0x4f4c,
    AOSVS = 0x5356,
    ExtendedTimestamp = 0x5455,
    XceedUnicode = 0x554e,
    InfoZIPUNIX = 0x5855,
    InfoZIPUTF8Comment = 0x6375,
    BeOS = 0x6542,
    Theos = 0x6854,
    InfoZIPUTF8Name = 0x7075,
    AtheOS = 0x7441,
    ASiUNIX = 0x756e,
    ZIPUNIX16bitUIDGIDInfo = 0x7855,
    ZIPUNIX3rdGenerationGenericUIDGIDInfo = 0x7875,
    MicrosoftOpenPackagingGrowthHint = 0xa220,
    DataStreamAlignment = 0xa11e,
    JavaJAR = 0xcafe,
    AndroidZIPAlignment = 0xd935,
    KoreanZIPCodePageInfo = 0xe57a,
    SMSQDOS = 0xfd4a,
    AExEncryptionStructure = 0x9901,
    Unknown = 0x9902,

    const Self = @This();
    pub fn from(v: u16) Self {
        return @enumFromInt(v);
    }

    pub fn code(self: Self) u16 {
        return @as(u16, @intFromEnum(self));
    }
};

pub const Zip64ExtendedInfo = struct {
    pub const CODE = ExtraFieldHeaderID.Zip64ExtendedInfo.code();

    data_size: u16,

    original_size: u64,
    compressed_size: u64,
    relative_header_offset: u64,
    disk_start_number: u32,
};

pub const ExtendedTimestamp = struct {
    pub const CODE = ExtraFieldHeaderID.ExtendedTimestamp.code();

    data_size: u16,

    flags: u8,
    tolm: u32,
};

pub const ZIPUNIX3rdGenerationGenericUIDGIDInfo = struct {
    pub const CODE = ExtraFieldHeaderID.ZIPUNIX3rdGenerationGenericUIDGIDInfo.code();

    data_size: u16,

    version: u8,
    uid_size: u8,
    uid: u32,
    gid_size: u8,
    gid: u32,
};

pub fn decodeExtraFields(buffer: Buffer, handler: anytype) !void {
    var s = std.io.fixedBufferStream(@constCast(&buffer).bytes());
    var r = s.reader();

    while (true) {
        const header = r.readInt(u16, .little) catch {
            return;
        };
        const dataSize = try r.readInt(u16, .little);

        const headerId = ExtraFieldHeaderID.from(header);
        switch (headerId) {
            .Zip64ExtendedInfo => {
                const original_size = try r.readInt(u64, .little);
                const compressed_size = try r.readInt(u64, .little);
                const relative_header_offset = try r.readInt(u64, .little);
                const disk_start_number = try r.readInt(u32, .little);

                try handler.exec(header, &Zip64ExtendedInfo{
                    .data_size = dataSize,
                    .original_size = original_size,
                    .compressed_size = compressed_size,
                    .relative_header_offset = relative_header_offset,
                    .disk_start_number = disk_start_number,
                });
            },
            .ExtendedTimestamp => {
                const flags = try r.readInt(u8, .little);
                const tolm = try r.readInt(u32, .little);

                try handler.exec(header, &ExtendedTimestamp{
                    .data_size = dataSize,
                    .flags = flags,
                    .tolm = tolm,
                });
            },
            .ZIPUNIX3rdGenerationGenericUIDGIDInfo => {
                const version = try r.readInt(u8, .little);
                switch (version) {
                    1 => {
                        const uidSize = try r.readInt(u8, .little);
                        const uid = try r.readInt(u32, .little);

                        const gidSize = try r.readInt(u8, .little);
                        const gid = try r.readInt(u32, .little);

                        try handler.exec(header, &ZIPUNIX3rdGenerationGenericUIDGIDInfo{
                            .data_size = dataSize,
                            .version = version,
                            .uid_size = uidSize,
                            .uid = uid,
                            .gid_size = gidSize,
                            .gid = gid,
                        });
                    },
                    else => {
                        std.debug.panic("header  {s} decoder not handled for version {!}\n", .{ ints.toHexBytes(u16, .lower, header), version });
                    },
                }
            },
            else => {
                std.debug.panic("header {s} decoder not handled\n", .{ints.toHexBytes(u16, .lower, header)});
            },
        }
    }
}

pub fn encodeExtraFields(buffer: Buffer, data: anytype) !void {
    _ = try buffer.write(ints.toBytes(u16, data.CODE, .little));

    const header = ExtraFieldHeaderID.from(data.CODE);
    switch (header) {
        .Zip64ExtendedInfo => {
            const s = @as(Zip64ExtendedInfo, data);
            _ = try buffer.write(ints.toBytes(u16, s.data_size, .little));
            _ = try buffer.write(ints.toBytes(u64, s.original_size, .little));
            _ = try buffer.write(ints.toBytes(u64, s.compressed_size, .little));
            _ = try buffer.write(ints.toBytes(u64, s.relative_header_offset, .little));
            _ = try buffer.write(ints.toBytes(u32, s.disk_start_number, .little));
        },
        .ExtendedTimestamp => {
            const s = @as(ExtendedTimestamp, data);
            _ = try buffer.write(ints.toBytes(u16, s.data_size, .little));
            _ = try buffer.write(ints.toBytes(u8, s.flags, .little));
            _ = try buffer.write(ints.toBytes(u32, s.tolm, .little));
        },
        .ZIPUNIX3rdGenerationGenericUIDGIDInfo => {
            const s = @as(ZIPUNIX3rdGenerationGenericUIDGIDInfo, data);
            _ = try buffer.write(ints.toBytes(u16, s.data_size, .little));
            _ = try buffer.write(ints.toBytes(u8, s.version, .little));

            switch (s.version) {
                1 => {
                    _ = try buffer.write(ints.toBytes(u8, s.uid_size, .little));
                    _ = try buffer.write(ints.toBytes(u32, s.uid, .little));

                    _ = try buffer.write(ints.toBytes(u8, s.gid_size, .little));
                    _ = try buffer.write(ints.toBytes(u32, s.gid, .little));
                },
                else => {
                    std.debug.panic("header  {s} decoder not handled for version {!}\n", .{ ints.toHexBytes(u16, .lower, header), s.version });
                },
            }
        },
        else => {
            std.debug.panic("header {s} decoder not handled\n", .{ints.toHexBytes(u16, .lower, header)});
        },
    }
}
