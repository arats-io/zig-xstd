const deBruijn64 = 0x03f79d71b4ca8b09;

const deBruijn64tab = [64]u8{
    0,  1,  56, 2,  57, 49, 28, 3,  61, 58, 42, 50, 38, 29, 17, 4,
    62, 47, 59, 36, 45, 43, 51, 22, 53, 39, 33, 30, 24, 18, 12, 5,
    63, 55, 48, 27, 60, 41, 37, 16, 46, 35, 44, 21, 52, 32, 23, 11,
    54, 26, 40, 15, 34, 20, 31, 10, 25, 14, 19, 9,  13, 8,  7,  6,
};
pub fn trailingZeros64(x: u64) i32 {
    if (x == 0) {
        return 64;
    }

    const positive = @as(i128, @intCast(x));
    const re = positive & (positive * -1);

    const idx: usize = @as(usize, @intCast(re * deBruijn64 >> (64 - 6)));
    return @as(i32, @intCast(deBruijn64tab[idx]));
}
