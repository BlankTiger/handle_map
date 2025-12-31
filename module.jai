// T  -> value type
// HT -> handle type
// HT is recommended to be created like this:
//
//     HT :: #type,distinct Handle;
//
Handle_Map :: struct(HT: Type, T: Type) {
    handles:        [..]HT;
    values:         [..]T;
    sparse_indices: [..]Sparse_Index;
    next:           u32;
}

Handle :: struct {
    idx: u32; @"range: 0..10"
    gen: u32; @"range: 0..10"
}

is_handle_variant :: ($$T: Type) -> bool {
    #import "Compiler";

    ti := cast(*Type_Info) T;
    if ti.type != .VARIANT return false;

    variant_ti := cast(*Type_Info_Variant) T;
    it_is := get_type(variant_ti.variant_of) == Handle;
    return it_is;
}

operator == :: (a: $T, b: T) -> bool #modify { return is_handle_variant(T); }{
    return a.idx == b.idx && a.gen == b.gen;
}

Sparse_Index :: struct {
    idx_or_next: u32;
    gen:         u32;
}

deinit :: (m: *Handle_Map) {
    array_free(m.handles);
    array_free(m.values);
    array_free(m.sparse_indices);
}

has_handle :: (m: Handle_Map($HT, $T), h: HT) -> bool {
    if h.idx < cast(u32, m.sparse_indices.count) {
        return m.sparse_indices[h.idx].gen == h.gen;
    }

    return false;
}

get :: (m: Handle_Map($HT, $T), h: HT) -> has_handle: bool, value: T {
    if h.idx < cast(u32, m.sparse_indices.count) {
        entry := m.sparse_indices[h.idx];
        if entry.gen == h.gen {
            return true, m.values[entry.idx_or_next];
        }
    }

    return false, .{};
}

get_ptr :: (m: *Handle_Map($HT, $T), h: HT) -> has_handle: bool, value: *T {
    if h.idx < cast(u32, m.sparse_indices.count) {
        entry := m.sparse_indices[h.idx];
        if entry.gen == h.gen {
            return true, *m.values[entry.idx_or_next];
        }
    }

    return false, null;
}

insert :: (m: *Handle_Map($HT, $T), value: T) -> HT {
    handle: HT;

    if m.next < cast(u32, m.sparse_indices.count) {
        entry := *m.sparse_indices[m.next];
        assert(entry.gen < U32_MAX, "Generation sparse indices overflow");

        entry.gen += 1;
        handle = .{
            gen = entry.gen,
            idx = m.next,
        };
        m.next = entry.idx_or_next;
        entry.idx_or_next = cast(u32, m.handles.count);

        array_add(*m.handles, handle);
        array_add(*m.values,  value);
    } else {
        assert(m.next < U32_MAX, "Index sparse indices overflow");

        handle = .{
            idx = cast(u32, m.sparse_indices.count),
            gen = 0,
        };
        sparse_idx: Sparse_Index = .{
            idx_or_next = cast(u32, m.handles.count),
            gen         = 0,
        };

        array_add(*m.sparse_indices, sparse_idx);
        array_add(*m.handles,        handle);
        array_add(*m.values,         value);

        m.next += 1;
    }

    return handle;
}

update :: (m: *Handle_Map($HT, $T), h: HT, value: T) -> updated: bool {
    has_handle, ptr := get_ptr(m, h);
    if has_handle {
        ptr.* = value;
        return true;
    }

    return false;
}

delete :: (m: *Handle_Map($HT, $T), h: HT) -> had_handle: bool, value: T {
    if h.idx < cast(u32, m.sparse_indices.count) {
        entry := *m.sparse_indices[h.idx];
        if entry.gen != h.gen return false, .{};

        idx := entry.idx_or_next;
        entry.gen += 1;
        entry.idx_or_next = m.next;
        m.next = h.idx;
        value := m.values[idx];

        array_unordered_remove_by_index(*m.handles, idx);
        array_unordered_remove_by_index(*m.values,  idx);

        if idx < cast(u32, m.handles.count) {
            m.sparse_indices[m.handles[idx].idx].idx_or_next = idx;
        }

        return true, value;
    }

    return false, .{};
}

for_expansion :: (m: *Handle_Map, body: Code, flags: For_Flags) #expand {
    for <=cast(bool)(flags & .REVERSE) i: 0..m.values.count-1 {
        #if flags & .POINTER {
            `it := *m.values[i];
        } else {
            `it := m.values[i];
        }

        `it_index := m.handles[i];
        #insert body;
    }
}

#scope_file

#import "Basic";
#import "Math";
