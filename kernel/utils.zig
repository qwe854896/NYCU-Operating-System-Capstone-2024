pub fn align_up(value: usize, size: usize) usize {
    return (value + size - 1) & ~(size - 1);
}
