// file modified by Kiana Bennett
// original by cheese3660

<*
    This module implements lowering a regular expression syntax tree into a set of non-deterministic finite automata
*>
module regex::runtime::lowering;
import regex::runtime::automata;
import regex::runtime::character_class;
import regex::runtime::parsing;
import regex::utf8;
import std::collections::list;
import std::collections::set;
import regex::runtime::states;


<*
    This is an unpacked version of an automaton edge

*>
struct AutomatonEdge @private {
    EdgeData associated_data;
    uint next_state;
    ushort capture_begin;
    ushort capture_end;
    TransitionType transition_type;
}

<*
    This describes a singular automaton 
*>
struct SingleAutomaton @private {
    uint begin;
    uint end;
    // List { List {AutomatonEdge } } states;
    List { usz } state_edges_begin;
    List { ushort } state_edge_count;
    List { AutomatonEdge } edges;
}

<* 
    This optimizes redundant states out of an automaton

    @param [&inout] self
*>
fn void SingleAutomaton.reduce(&self) @private 
{
    @pool() 
    {
        bool[] keep = mem::temp_array(bool, self.state_edges_begin.len());
        for (usz i = 0; i < self.state_edges_begin.len(); i++) keep[i] = false;
        keep[self.end] = true;
        keep[self.begin] = true;

        // Keep all states that either
        // 1. Have a non-epsilon transition coming into them
        // 2. Have an edge coming out of them that begins or ends a capture group
        // or
        // 3. Have an edge coming into them that begins or ends a capture group
        //
        // 2 is necessary because of how we store capture groups in memory in the engine itself
        for (usz analyzing = 0; analyzing < self.state_edges_begin.len(); analyzing++) 
        {
            usz begin = self.state_edges_begin[analyzing];
            ushort count = self.state_edge_count[analyzing];
            
            for (usz edge_index = begin; edge_index < begin + count; edge_index++) {
                AutomatonEdge *edge = &self.edges[edge_index];
                if (edge.next_state == self.end) continue;
                if (edge.transition_type != EPSILON) keep[edge.next_state] = true;
                
                if (edge.capture_begin != 0 || edge.capture_end != 0) {
                    keep[edge.next_state] = true;
                    keep[analyzing] = true;
                }
            }
        }
        
        uint[] remap = mem::temp_array(uint, self.state_edges_begin.len());

        usz[] old_begin = self.state_edges_begin.to_tarray();
        ushort[] old_count = self.state_edge_count.to_tarray();
        AutomatonEdge[] old_edges = self.edges.to_tarray();

        self.state_edges_begin.clear();
        self.state_edge_count.clear();
        self.edges.clear();


        List { uint } state_stack;
        List { usz }  edge_stack;

        for (uint reducing = 0; reducing < old_begin.len; reducing++) 
        {
            if (reducing == self.end) {
                remap[reducing] = (uint)self.state_edges_begin.len();
                self.state_edges_begin.push(0);
                self.state_edge_count.push(0);
                continue;
            }

            if (!keep[reducing]) continue;
            
            state_stack.clear();
            edge_stack.clear();
            state_stack.push(reducing);
            edge_stack.push(0);

            usz new_edge_begin = self.edges.len();
            ushort new_count = 0;

            while (state_stack.len() > 0) 
            {
                uint cur_state_idx = state_stack.pop()!!;
                usz cur_edge_idx = edge_stack.pop()!!;

                if (cur_edge_idx + 1 < old_count[cur_state_idx]) 
                {
                    state_stack.push(cur_state_idx);
                    edge_stack.push(cur_edge_idx + 1);
                }

                AutomatonEdge edge = old_edges[old_begin[cur_state_idx] + cur_edge_idx];

                if (!keep[edge.next_state]) 
                {
                    state_stack.push(edge.next_state);
                    edge_stack.push(0);
                } 
                else 
                {
                    self.edges.push(edge);
                    new_count += 1;
                }
            }

            remap[reducing] = (uint)self.state_edges_begin.len();
            self.state_edges_begin.push(new_edge_begin);
            self.state_edge_count.push(new_count);
        }

        foreach (&edge : self.edges)
        {
            edge.next_state = remap[edge.next_state];
        }

        self.begin = remap[self.begin];
        self.end = remap[self.end];
    };
}

<*
    This inserts an automaton into an NfaRegex

    @param [&in] self
    @param [&inout] regex   : "The regex being lowered into"
    @param automaton_index   : "The index of this automaton in the regex"
    @param state_offset      : "The offset of the first state of this automaton"
    @param edge_offset       : "The offset of the first edge of this automaton"

    @require automaton_index < regex.automaton_count : "Invalid automaton index"
    @require state_offset + self.state_edges_begin.len() <= regex.state_count : "Invalid state offset"
    @require edge_offset + self.edges.len() <= regex.edge_count : "Invalid edge offset"
*>
fn void SingleAutomaton.insert_into(&self, NfaRegex *regex, ushort automaton_index, uint state_offset, usz edge_offset) @private
{
    regex.automaton_begin[automaton_index] = self.begin + state_offset;
    regex.automaton_end[automaton_index] = self.end + state_offset;
    foreach (i, edgesBegin : self.state_edges_begin) 
    {
        regex.state_edges_begin[i + state_offset] = edgesBegin + edge_offset;
        regex.state_edge_count[i + state_offset] = self.state_edge_count[i];
    }

    foreach (i, &edge : self.edges) 
    {
        regex.edge_to[i + edge_offset] = edge.next_state + state_offset;
        regex.transition_type[i + edge_offset] = edge.transition_type;
        regex.edge_capture_begin[i + edge_offset] = edge.capture_begin;
        regex.edge_capture_end[i + edge_offset] = edge.capture_end;
        regex.edge_associated_data[i + edge_offset] = edge.associated_data;
    }
}

struct InternedStringInfo @private
{
    usz begin;
    usz len;
}


<*
    Intern a string into a dstring

    @param to_intern : "The string to intern"
    @param [&in] internment_cache : "The cache to intern it to"

    @return "The position in the interment cache of the string"
*>
fn InternedStringInfo intern_string(String to_intern, DString *internment_cache) @private 
{
    if (try index = internment_cache.str_view().index_of(to_intern)) 
    {
        return {index, to_intern.len};
    } 
    else 
    {
        usz index = internment_cache.len();
        internment_cache.append_string(to_intern);
        return {index, to_intern.len};
    }
}

<*
    Intern a character class

    @param to_intern : "The character class to intern"
    @param [&in] internment_cache

    @return "The index to be used for edge associated data"
*>
fn uint intern_character_class(CharacterClass to_intern, List { CharacterClass } *internment_cache) {
    for (uint i = 0; i < internment_cache.len(); i++) 
    {
        if (to_intern == internment_cache.get(i)) 
        {
            return i;
        }
    }

    internment_cache.push(to_intern);
    return (uint)(internment_cache.len() - 1);
}

<*
    Struct caching information about a lowered subautomaton

    (This is necessary for when we repeat nodes and)
*>
struct LoweredSubAutomaton @private
{
    Node* entry_node;
    SingleAutomaton sub_automaton;
}

struct LoweringContext @private
{
    List { LoweredSubAutomaton }* sub_automata;
    List { CharacterClass }* character_internment_cache;
    DString* string_interment_cache;
    HashSet { usz /* Node* */}* failed_string_conversions;
    ushort* max_capture_group_index;
    SingleAutomaton automaton;
    Options options;
}

// All that's needed here is a way to lower a regex to a non-deterministic finite automata
struct AutomatonLoweringResult @private
{
    uint begin;
    uint end;
}

fn ushort? LoweringContext.get_sub_automaton(&self, Node* sub_automaton) @private
{
    if (self.sub_automata.len() >= ushort.max) return regex::REGEX_TOO_COMPLEX?;

    for (ushort i = 0; i < self.sub_automata.len(); i++)
    {
        if (self.sub_automata.get(i).entry_node == sub_automaton) return i + 1;
    }

    ushort i = (ushort)self.sub_automata.len();
    self.sub_automata.push({sub_automaton, {}});

    LoweringContext child = {
        self.sub_automata,
        self.character_internment_cache,
        self.string_interment_cache,
        self.failed_string_conversions,
        self.max_capture_group_index,
        {},
        self.options
    };

    AutomatonLoweringResult result = child.lower(sub_automaton)!;
    child.automaton.begin = result.begin;
    child.automaton.end = result.end;
    (*self.sub_automata)[i].sub_automaton = child.automaton;

    return i + 1;
}

<*
    Get a state with a given amount of edges
*>
fn uint? LoweringContext.get_next_state(&self, uint allocated_edges = 1) @private
{
    if (allocated_edges >= 0xFFFFFF) return regex::REGEX_TOO_COMPLEX?;
    if (self.automaton.state_edge_count.len() >= 0xFFFFFF) return regex::REGEX_TOO_COMPLEX?;
    uint idx = (uint)self.automaton.state_edge_count.len();
    self.automaton.state_edge_count.push(0);
    self.automaton.state_edges_begin.push(self.automaton.edges.len());
    for (usz i = 0; i < allocated_edges; i++)
    {
        self.automaton.edges.push({});
    }
    return idx;
}

<*
    Add a transition to a state
    
    @require state < self.automaton.state_edges_begin.len() : "Invalid starting state number!"
    @require next_state < self.automaton.state_edges_begin.len() : "Invalid ending state number!"

    @require self.automaton.state_edges_begin[state] + self.automaton.state_edge_count[state] < self.automaton.edges.len() : "Invalid edge index!"
*>
fn void LoweringContext.add_transition(&self, uint state, uint next_state, TransitionType transition = EPSILON, EdgeData data = {}, ushort capture_begin = 0, ushort capture_end = 0) @private
{
    if (capture_begin > *self.max_capture_group_index) *self.max_capture_group_index = capture_begin;
    if (capture_end > *self.max_capture_group_index) *self.max_capture_group_index = capture_end;

    usz index = self.automaton.state_edges_begin[state] + self.automaton.state_edge_count[state]++;
    
    self.automaton.edges[index] = {
        data,
        next_state,
        capture_begin,
        capture_end,
        transition
    };
}

faultdef IS_NOT_A_STRING_TREE;

<*
    Append a node to a string tree

    @param [&in] node : "The node to append"
    @param builder    : "The builder to append it to"

    @return? IS_NOT_A_STRING_TREE : "If the node cannot be converted to a string"
*>
fn void? LoweringContext.get_string_build(&self, Node* node, DString* builder) @private
{
    if (self.failed_string_conversions.contains((uptr)node)) return IS_NOT_A_STRING_TREE?;
    defer catch self.failed_string_conversions.add((uptr)node);

    switch (node.type)
    {
        case CHARACTER:
            if (self.options & Options.ASCII_ONLY) 
            {
                builder.reserve(node.character.repeat_count);
                for (uint i = 0; i < node.character.repeat_count; i++)
                {
                    builder.append_char((char)node.character.character);
                }
            } 
            else 
            {
                // builder.reserve(node.character.repeat_count);
                builder.reserve(utf8::get_len(node.character.character) * node.character.repeat_count);
                for (uint i = 0; i < node.character.repeat_count; i++)
                {
                    builder.append_char32(node.character.character);
                }
            }
        case EXACTLY:
            @pool()
            {
                DString child_builder;
                child_builder.tinit();
                self.get_string_build(node.node_and_number.child, &child_builder)!;

                for (uint i = 0; i < node.node_and_number.repeat_count; i++)
                {
                    builder.append_dstring(child_builder);
                }
            };
        case CONCAT:
            self.get_string_build(node.binary.lhs,builder)!;
            self.get_string_build(node.binary.rhs,builder)!;
        default:
            return IS_NOT_A_STRING_TREE?;
    }
}

<*
    Build the node into a string if it is possible

    @param [&in] node : "The node to check"

    @return  "The interned string information"
    @return? IS_NOT_A_STRING_TREE : "If the node cannot be converted to a string"
*>
fn InternedStringInfo? LoweringContext.get_string(&self, Node* node) @private
{
    @pool()
    {
        DString result;
        result.tinit();
        if (try self.get_string_build(node, &result))
        {
            return intern_string(result.str_view(),self.string_interment_cache);
        }
        return IS_NOT_A_STRING_TREE?;
    };
}

<*
    Lower a single regex node

    @param [&in] node
    @param required_end_edge_count : "The amount of edges required at the end node"
    @return "A lowering result consisting of a beginning and ending in the current automaton"

    @return? regex::REGEX_TOO_COMPLEX : "If the regex becomes too complex in the process of lowering"
*>
fn AutomatonLoweringResult? LoweringContext.lower(&self, Node* node, uint required_end_edge_count = 0) @private
{
    if (try info = self.get_string(node))
    {
        uint begin = self.get_next_state(1)!;
        uint end = self.get_next_state(required_end_edge_count)!;
        self.add_transition(begin, end, STRING, {.string = {(uint)info.begin, (uint)info.len}});
        return {begin, end};
    }
    switch (node.type)
    {
        case WILDCARD:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            self.add_transition(begin,end, WILDCARD, {.wildcard = {node.repeat_count}});
            return {begin, end};
        case CHARACTER:
            unreachable("All characters should have become strings!");
        case BACKREF:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            self.add_transition(begin,end,BACK_REFERENCE, {.back_reference = {node.backref.group_id, node.backref.repeat_count}});
            return {begin, end};
        case POSITIVE_CG:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            uint interned = intern_character_class(node.character_group.class, self.character_internment_cache);
            self.add_transition(begin,end,POS_CHARACTER, {.character = {interned, node.character_group.repeat_count}});
            return {begin, end};
        case NEGATIVE_CG:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            uint interned = intern_character_class(node.character_group.class, self.character_internment_cache);
            self.add_transition(begin,end,NEG_CHARACTER, {.character = {interned, node.character_group.repeat_count}});
            return {begin, end};
        case START_ANCHOR:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            self.add_transition(begin,end,START);
            return {begin, end};
        case END_ANCHOR:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            self.add_transition(begin,end,END);
            return {begin, end};
        case WORD_ANCHOR:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            self.add_transition(begin,end,WORD_BOUNDARY);
            return {begin, end};
        case NOT_WORD_ANCHOR:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            self.add_transition(begin,end,NOT_WORD_BOUNDARY);
            return {begin, end};
        case POSITIVE_LOOKAHEAD:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            self.add_transition(begin,end,POS_LOOKAHEAD,{.sub_automaton_index = self.get_sub_automaton(node.child)!});
            return {begin, end};
        case NEGATIVE_LOOKAHED:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            self.add_transition(begin,end,NEG_LOOKAHEAD,{.sub_automaton_index = self.get_sub_automaton(node.child)!});
            return {begin, end};
        case CAPTURE_GROUP:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            AutomatonLoweringResult child = self.lower(node.capture_group.child, 1)!;
            self.add_transition(begin, child.begin, capture_begin: node.capture_group.group_id);
            self.add_transition(child.end, end, capture_end: node.capture_group.group_id);
            return {begin, end};
        case ZERO_OR_ONE:
            uint begin = self.get_next_state(2)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            AutomatonLoweringResult child = self.lower(node.child, 1)!;
            self.add_transition(begin, child.begin);
            self.add_transition(begin, end);
            self.add_transition(child.end, end);
            return {begin, end};
        case ZERO_OR_MORE:
            uint begin = self.get_next_state(2)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            AutomatonLoweringResult child = self.lower(node.child, 1)!;
            self.add_transition(begin, child.begin);
            self.add_transition(begin, end);
            self.add_transition(child.end, begin);
            return {begin, end};
        case ONE_OR_MORE:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            AutomatonLoweringResult child = self.lower(node.child, 2)!;
            self.add_transition(begin, child.begin);
            self.add_transition(child.end, begin);
            self.add_transition(child.end, end);
            return {begin, end};
        case EXACTLY:
            uint begin = self.get_next_state(1)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            uint previous = begin;
            for (uint i = 0; i < node.node_and_number.repeat_count; i++)
            {
                AutomatonLoweringResult child = self.lower(node.node_and_number.child, 1)!;
                self.add_transition(previous, child.begin);
                previous = child.end;
            }
            self.add_transition(previous, end);
            return {begin, end};
        case AT_MOST:
            uint begin = self.get_next_state(2)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            uint previous = begin;
            for (uint i = 0; i < node.node_and_number.repeat_count; i++)
            {
                AutomatonLoweringResult child = self.lower(node.node_and_number.child, (i + 1 == node.node_and_number.repeat_count) ? 1 : 2)!;
                self.add_transition(previous, child.begin);
                self.add_transition(previous, end);
                previous = child.end;
            }
            self.add_transition(previous, end);
            return {begin, end};
        case CONCAT:
            AutomatonLoweringResult left = self.lower(node.binary.lhs, 1)!;
            AutomatonLoweringResult right = self.lower(node.binary.rhs, required_end_edge_count)!;
            self.add_transition(left.end, right.begin);
            return {left.begin, right.end};
        case DISJUNCT:
            uint begin = self.get_next_state(2)!;
            uint end = self.get_next_state(required_end_edge_count)!;
            AutomatonLoweringResult left = self.lower(node.binary.lhs, 1)!;
            AutomatonLoweringResult right = self.lower(node.binary.rhs, 1)!;

            self.add_transition(begin, left.begin);
            self.add_transition(begin, right.begin);
            self.add_transition(left.end, end);
            self.add_transition(right.end, end);
            return {begin, end};
    }
}


<*
    Compile a regex into a set of automata, and epsilon reduce it
    
    @param regex_str  : "The string to compile into a set of automata"
    @param options   : "The options that the regex uses"
    @param allocator : "The memory allocator to allocate the regex with"

    @return "A NFA representing a regex"
*>
fn NfaRegex? compile_regex(String regex_str, Options options = NONE, Allocator allocator = mem)
{
    @pool()
    {
        Node* regex = parsing::parse_regex(regex_str, options)!;
        List { LoweredSubAutomaton } subautomata;
        List { CharacterClass } classes;
        HashSet { usz } failed_string_conversions;
        DString strings;
        subautomata.tinit();
        classes.tinit();
        strings.tinit();
        failed_string_conversions.tinit();
        ushort max_capture_group_index;
        LoweringContext root_context = {&subautomata, &classes, &strings, &failed_string_conversions, &max_capture_group_index, {}, options};
        AutomatonLoweringResult result = root_context.lower(regex)!;
        root_context.automaton.begin = result.begin;
        root_context.automaton.end = result.end;

        if (options & Options.NO_REDUCTION == 0)
        {
            root_context.automaton.reduce();
            foreach (&automaton : subautomata)
            {
                automaton.sub_automaton.reduce();
            }
        }

        usz state_count = root_context.automaton.state_edge_count.len();
        usz edge_count = root_context.automaton.edges.len();

        foreach (&edge : root_context.automaton.edges)
        {
            if (edge.transition_type == BACK_REFERENCE && edge.associated_data.back_reference.capture_group_index > max_capture_group_index) return regex::INVALID_CAPTURE_GROUP_ID?;
        }
        
        // Now let's do some analyses
        foreach (&automaton : subautomata)
        {
            state_count += automaton.sub_automaton.state_edge_count.len();
            edge_count += automaton.sub_automaton.edges.len();
            foreach (&edge : automaton.sub_automaton.edges) 
            {
            if (edge.transition_type == BACK_REFERENCE && edge.associated_data.back_reference.capture_group_index > max_capture_group_index) return regex::INVALID_CAPTURE_GROUP_ID?;
            }
        }

        if (state_count >= 0x1000000)
        {
            return regex::REGEX_TOO_COMPLEX?;
        }

        CharacterClass[] allocated_classes = allocator::new_array(allocator, CharacterClass, classes.len());
        for (usz i = 0; i < allocated_classes.len; i++) allocated_classes[i] = classes[i].copy(allocator);

        NfaRegex res =
        {
            allocator,
            (ushort)subautomata.len() + 1,
            allocator::new_array(allocator, uint, subautomata.len() + 1),
            allocator::new_array(allocator, uint, subautomata.len() + 1),
            (uint)state_count,
            allocator::new_array(allocator, usz, state_count),
            allocator::new_array(allocator, ushort, state_count),
            edge_count,
            allocator::new_array(allocator, uint, edge_count),
            allocator::new_array(allocator, TransitionType, edge_count),
            allocator::new_array(allocator, ushort, edge_count),
            allocator::new_array(allocator, ushort, edge_count),
            allocator::new_array(allocator, EdgeData, edge_count),
            allocated_classes,
            strings.copy_str(allocator),
            max_capture_group_index,
            options
        };


        root_context.automaton.insert_into(&res, 0, 0, 0);
        usz state_offset = root_context.automaton.state_edge_count.len();;
        usz edge_offset = root_context.automaton.edges.len();
        foreach (ushort i, &automaton : subautomata)
        {
            automaton.sub_automaton.insert_into(&res, i+1, (uint)state_offset, edge_offset);
            state_offset += automaton.sub_automaton.state_edge_count.len();
            edge_offset += automaton.sub_automaton.edges.len();
        }
        return res;
    };
}
