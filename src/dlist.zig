pub const DList = struct {
    prev: *DList = null,
    next: *DList = null,

    pub inline fn init(node: *DList) void {
        node.prev = node;
        node.next = node;
    }

    pub inline fn is_empty(node: *DList) bool {
        return node.next == node;
    }

    pub inline fn detach(node: *DList) void {
        const prev = node.prev;
        const next = node.next;
        prev.next = next;
        next.prev = prev;
    }

    pub inline fn prepend(target: *DList, node: *DList) void {
        const prev = target.prev;
        prev.next = node;
        target.prev = node;
        node.prev = prev;
        node.next = target;
    }
};
