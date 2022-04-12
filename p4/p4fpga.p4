#include <core.p4>
#include <tna.p4>

#define SEQ_SUP

/*************************************************************************
 ************* C O N S T A N T S    A N D   T Y P E S  *******************
 *************************************************************************/
const bit<16> ETHERTYPE_IPV4 = 0x0800;
const bit<16> ETHERTYPE_ARP  = 0x0806;

const bit<8> IPV4_PROTOCOL_TCP = 6;
const bit<8> IPV4_PROTOCOL_UDP = 17;

const int IPV4_HOST_SIZE = 65536;
const int IPV4_LPM_SIZE  = 12288;

// parameters
#define NODE_SIZE     1

#define INDEX_WIDTH   16
#define INDEX_SLOT    17
#define INDEX_SIZE    65536 // 2 ^ (INDEX_SLOT - 1)

#define VALUE_WIDTH   32

#define COUNTER_WIDTH 32

#define BITMAP_WIDTH  32

#define SEQ_WIDTH     32

/*************************************************************************
 ***********************  H E A D E R S  *********************************
 *************************************************************************/

/*  Define all the headers the program will recognize             */
/*  The actual sets of headers processed by each gress can differ */

/* Standard ethernet header */
header ethernet_h
{
    bit<48> dst_addr;
    bit<48> src_addr;
    bit<16> ether_type;
}

header arp_h
{
    bit<16> hw_type;
    bit<16> proto_type;
    bit<8>  hw_addr_len;
    bit<8>  proto_addr_len;
    bit<16> opcode;

    bit<48> src_hw_addr;
    bit<32> src_proto_addr;
    bit<48> dst_hw_addr;
    bit<32> dst_proto_addr;
}

header ipv4_h
{
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> total_len;
    bit<16> identification;
    bit<3>  flags;
    bit<13> frag_offset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdr_checksum;
    bit<32> src_addr;
    bit<32> dst_addr;
}

header tcp_h
{
    bit<16> src_port;
    bit<16> dst_port;
    bit<32> seq_no;
    bit<32> ack_no;
    bit<4>  data_offset;
    bit<3>  res;
    bit<3>  ecn;
    bit<6>  ctrl;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgent_ptr;
}

header udp_t
{
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> len;
    bit<16> checksum;
}

/* Customized struct */

header payload_t
{
    bit<15> __pad0;
    bit<1>    slot;
    bit<16>  index;
    bit<32> seq_no;
    bit<32> bitmap;

    bit<32> map_state;
    bit<32> counter_state;
    bit<1>  slot_state;

    bit<95> __pad1;

    bit<32> value1;
    bit<32> value2;
    bit<32> value3;
    bit<32> value4;
    bit<32> value5;
    bit<32> value6;
    bit<32> value7;
    bit<32> value8;
}

#define VALUE_REG(s, i)                                                               \
    Register<bit<VALUE_WIDTH>, bit<INDEX_WIDTH>>(INDEX_SIZE) value_##s####i##_reg;    \
    RegisterAction<bit<VALUE_WIDTH>,                                                  \
                   bit<INDEX_WIDTH>,                                                  \
                   bit<VALUE_WIDTH>>(value_##s####i##_reg)                            \
    value_##s####i##_add = {                                                          \
        void apply(inout bit<VALUE_WIDTH> register_data, out bit<VALUE_WIDTH> result) \
        {                                                                             \
            register_data = register_data + hdr.load.value##i##;                      \
            result = register_data;                                                   \
        }                                                                             \
    };                                                                                \
    RegisterAction<bit<VALUE_WIDTH>,                                                  \
                   bit<INDEX_WIDTH>,                                                  \
                   bit<VALUE_WIDTH>>(value_##s####i##_reg)                            \
    value_##s####i##_clr = {                                                          \
        void apply(inout bit<VALUE_WIDTH> register_data, out bit<VALUE_WIDTH> result) \
        {                                                                             \
            result = register_data;                                                   \
            register_data = 0;                                                        \
        }                                                                             \
    }


/*************************************************************************
 **************  I N G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
 
/***********************  H E A D E R S  ************************/

struct my_ingress_headers_t
{
    ethernet_h ethernet;
    arp_h      arp;
    ipv4_h     ipv4;
    tcp_h      tcp;
    udp_t      udp;
    payload_t  load;
}

/******  G L O B A L   I N G R E S S   M E T A D A T A  *********/

struct my_ingress_metadata_t
{
    bit<32> dst_ipv4;
}

/***********************  P A R S E R  **************************/

// see includes/parsers.p4
parser IngressParser(packet_in       pkt,
    /* User */    
    out my_ingress_headers_t         hdr,
    out my_ingress_metadata_t        meta,
    /* Intrinsic */
    out ingress_intrinsic_metadata_t ig_intr_md)
{
    /* This is a mandatory state, required by Tofino Architecture */
    state start
    {
        pkt.extract(ig_intr_md);
        pkt.advance(PORT_METADATA_SIZE);
        transition meta_init;
    }

    state meta_init
    {
        meta.dst_ipv4 = 0;
        transition parse_load;
    }

    state parse_ethernet
    {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type)
        {
            ETHERTYPE_IPV4: parse_ipv4;
            ETHERTYPE_ARP : parse_arp;
            default       : accept;
        }
    }

    state parse_arp
    {
        pkt.extract(hdr.arp);
        meta.dst_ipv4 = hdr.arp.dst_proto_addr;
        
        transition accept;
    }

    state parse_ipv4
    {
        pkt.extract(hdr.ipv4);
        meta.dst_ipv4 = hdr.ipv4.dst_addr;

        transition select(hdr.ipv4.protocol)
        {
            IPV4_PROTOCOL_TCP: parse_tcp;
            IPV4_PROTOCOL_UDP: parse_udp;
            default          : accept;
        }
    }

    state parse_tcp
    {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp
    {
        pkt.extract(hdr.udp);
        transition accept;
    }

    state parse_load
    {
        pkt.extract(hdr.load);
        transition accept;
    }
}

/***************** M A T C H - A C T I O N  *********************/

control Ingress(
    /* User */
    inout my_ingress_headers_t                      hdr,
    inout my_ingress_metadata_t                     meta,
    /* Intrinsic */
    in    ingress_intrinsic_metadata_t              ig_intr_md,
    in    ingress_intrinsic_metadata_from_parser_t  ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t       ig_tm_md)
{
    // forward
    action send(PortId_t port)
    {
        ig_tm_md.ucast_egress_port = port;
    }

    action multicast(MulticastGroupId_t mcast_grp)
    {
        ig_tm_md.mcast_grp_a = mcast_grp;
    }

    // flag
    bit<1> slot;

    bool add_0;
    bool add_1;
    bool clr_0;
    bool clr_1;

    bit<BITMAP_WIDTH> bitmap;

    bit<BITMAP_WIDTH> status0;
    bit<BITMAP_WIDTH> status1;
    bit<COUNTER_WIDTH> n_node;

    // value reg
    VALUE_REG(0, 1);
    VALUE_REG(0, 2);
    VALUE_REG(0, 3);
    VALUE_REG(0, 4);
    VALUE_REG(0, 5);
    VALUE_REG(0, 6);
    VALUE_REG(0, 7);
    VALUE_REG(0, 8);

    VALUE_REG(1, 1);
    VALUE_REG(1, 2);
    VALUE_REG(1, 3);
    VALUE_REG(1, 4);
    VALUE_REG(1, 5);
    VALUE_REG(1, 6);
    VALUE_REG(1, 7);
    VALUE_REG(1, 8);

    // counter
    Register<bit<COUNTER_WIDTH>, bit<INDEX_WIDTH>>(INDEX_SIZE) counter_reg_0;
    RegisterAction<bit<COUNTER_WIDTH>,
                   bit<INDEX_WIDTH>,
                   bit<COUNTER_WIDTH>>(counter_reg_0)
    count_0 = {
        void apply(inout bit<COUNTER_WIDTH> register_data, out bit<COUNTER_WIDTH> result)
        {
            register_data = register_data + 1;
            result = register_data;
        }
    };
    RegisterAction<bit<COUNTER_WIDTH>,
                   bit<INDEX_WIDTH>,
                   bit<COUNTER_WIDTH>>(counter_reg_0)
    get_counter_0 = {
        void apply(inout bit<COUNTER_WIDTH> register_data, out bit<COUNTER_WIDTH> result)
        {
            result = register_data;
        }
    };

    Register<bit<COUNTER_WIDTH>, bit<INDEX_WIDTH>>(INDEX_SIZE) counter_reg_1;
    RegisterAction<bit<COUNTER_WIDTH>,
                   bit<INDEX_WIDTH>,
                   bit<COUNTER_WIDTH>>(counter_reg_1)
    count_1 = {
        void apply(inout bit<COUNTER_WIDTH> register_data, out bit<COUNTER_WIDTH> result)
        {
            register_data = register_data + 1;
            result = register_data;
        }
    };
    RegisterAction<bit<COUNTER_WIDTH>,
                   bit<INDEX_WIDTH>,
                   bit<COUNTER_WIDTH>>(counter_reg_1)
    get_counter_1 = {
        void apply(inout bit<COUNTER_WIDTH> register_data, out bit<COUNTER_WIDTH> result)
        {
            result = register_data;
        }
    };

    // node map
    Register<bit<BITMAP_WIDTH>, bit<INDEX_WIDTH>>(INDEX_SIZE) node_map_reg_0;
    RegisterAction<bit<BITMAP_WIDTH>,
                   bit<INDEX_WIDTH>,
                   bit<BITMAP_WIDTH>>(node_map_reg_0)
    node_map_merge_0 = {
        void apply(inout bit<BITMAP_WIDTH> register_data, out bit<BITMAP_WIDTH> result)
        {
            bit<BITMAP_WIDTH> temp = register_data & bitmap;
            register_data = register_data | bitmap;
            result = temp;
        }
    };
    RegisterAction<bit<BITMAP_WIDTH>,
                   bit<INDEX_WIDTH>,
                   bit<BITMAP_WIDTH>>(node_map_reg_0)
    node_map_clear_0 = {
        void apply(inout bit<BITMAP_WIDTH> register_data, out bit<BITMAP_WIDTH> result)
        {
            bit<BITMAP_WIDTH> temp = ~(register_data) & bitmap;
            register_data = register_data & ~(bitmap);
            result = temp;
        }
    };

    Register<bit<BITMAP_WIDTH>, bit<INDEX_WIDTH>>(INDEX_SIZE) node_map_reg_1;
    RegisterAction<bit<BITMAP_WIDTH>,
                   bit<INDEX_WIDTH>,
                   bit<BITMAP_WIDTH>>(node_map_reg_1)
    node_map_merge_1 = {
        void apply(inout bit<BITMAP_WIDTH> register_data, out bit<BITMAP_WIDTH> result)
        {
            bit<BITMAP_WIDTH> temp = register_data & bitmap;
            register_data = register_data | bitmap;
            result = temp;
        }
    };
    RegisterAction<bit<BITMAP_WIDTH>,
                   bit<INDEX_WIDTH>,
                   bit<BITMAP_WIDTH>>(node_map_reg_1)
    node_map_clear_1 = {
        void apply(inout bit<BITMAP_WIDTH> register_data, out bit<BITMAP_WIDTH> result)
        {
            bit<BITMAP_WIDTH> temp = ~(register_data) & bitmap;
            register_data = register_data & ~(bitmap);
            result = temp;
        }
    };

    // bitmap table
    action get_bitmap(bit<BITMAP_WIDTH> map)
    {
        bitmap = map;
    }

    action use_default_bitmap()
    {
        bitmap = hdr.load.bitmap;
    }

    table bitmap_mapping
    {
        key = {
            hdr.load.bitmap: exact;
            ig_intr_md.ingress_port: exact;
        }
        actions = {
            get_bitmap;
            use_default_bitmap;
        }
        const entries = {
            (0,   0) : get_bitmap(1 <<  0);
            (0,   4) : get_bitmap(1 <<  1);
            (0,   8) : get_bitmap(1 <<  2);
            (0,  12) : get_bitmap(1 <<  3);
            (0,  16) : get_bitmap(1 <<  4);
            (0,  20) : get_bitmap(1 <<  5);
            (0,  24) : get_bitmap(1 <<  6);
            (0,  28) : get_bitmap(1 <<  7);
            (0,  32) : get_bitmap(1 <<  8);
            (0,  36) : get_bitmap(1 <<  9);
            (0,  40) : get_bitmap(1 << 10);
            (0,  44) : get_bitmap(1 << 11);
            (0,  48) : get_bitmap(1 << 12);
            (0,  52) : get_bitmap(1 << 13);
            (0,  56) : get_bitmap(1 << 14);
            (0,  60) : get_bitmap(1 << 15);
            (0, 128) : get_bitmap(1 << 16);
            (0, 132) : get_bitmap(1 << 17);
            (0, 136) : get_bitmap(1 << 18);
            (0, 140) : get_bitmap(1 << 19);
            (0, 144) : get_bitmap(1 << 20);
            (0, 148) : get_bitmap(1 << 21);
            (0, 152) : get_bitmap(1 << 22);
            (0, 156) : get_bitmap(1 << 23);
            (0, 160) : get_bitmap(1 << 24);
            (0, 164) : get_bitmap(1 << 25);
            (0, 168) : get_bitmap(1 << 26);
            (0, 172) : get_bitmap(1 << 27);
            (0, 176) : get_bitmap(1 << 28);
            (0, 180) : get_bitmap(1 << 29);
            (0, 184) : get_bitmap(1 << 30);
            (0, 188) : get_bitmap(1 << 31);
        }
        const default_action = use_default_bitmap();
    }

    // seq
    Register<bit<SEQ_WIDTH>, PortId_t>(256) seq_reg;
    RegisterAction<bit<SEQ_WIDTH>,
                   PortId_t,
                   bool>(seq_reg)
    seq_check = {
        void apply(inout bit<SEQ_WIDTH> register_data, out bool result)
        {
            #ifdef SEQ_SUP
            if(hdr.load.seq_no > register_data || hdr.load.seq_no == 0)
            {
            #endif
                register_data = hdr.load.seq_no;
                result = true;
            #ifdef SEQ_SUP
            }
            else
            {
                result = false;
            }
            #endif
        }
    };
    
    apply
    {
        if(hdr.load.isValid())
        {
            // slot = hdr.load.index[INDEX_SLOT:INDEX_SLOT];
            slot = hdr.load.slot;
            add_0 = false;
            add_1 = false;
            clr_0 = false;
            clr_1 = false;
            
            bitmap_mapping.apply();

            if(bitmap != 0 && seq_check.execute(ig_intr_md.ingress_port))
            {
                if(slot == 0)
                {
                    status0 = node_map_merge_0.execute(hdr.load.index);
                    status1 = node_map_clear_1.execute(hdr.load.index);
                    if(status0 == 0) // haven't aggregated
                    {
                        n_node = count_0.execute(hdr.load.index);
                        add_0 = true;
                    }
                    else
                    {
                        n_node = get_counter_0.execute(hdr.load.index);
                    }

                    if(n_node % NODE_SIZE == 0) // fulfilled
                    {
                        if(status0 == 0)
                        {
                            clr_1 = true;
                            multicast(1);
                        }
                        else
                        {
                            send(ig_intr_md.ingress_port);
                        }
                    }
                    else
                    {
                        send(192);

                        hdr.load.counter_state = n_node;
                        hdr.load.map_state = status0;
                        hdr.load.slot_state = slot;
                    }
                }
                else
                {
                    status0 = node_map_clear_0.execute(hdr.load.index);
                    status1 = node_map_merge_1.execute(hdr.load.index);
                    if(status1 == 0) // haven't aggregated
                    {
                        n_node = count_1.execute(hdr.load.index);
                        add_1 = true;
                    }
                    else
                    {
                        n_node = get_counter_1.execute(hdr.load.index);
                    }

                    if(n_node % NODE_SIZE == 0) // fulfilled
                    {
                        if(status1 == 0)
                        {
                            clr_0 = true;
                            multicast(1);
                        }
                        else
                        {
                            send(ig_intr_md.ingress_port);
                        }
                    }
                    else
                    {
                        send(192);

                        hdr.load.counter_state = n_node;
                        hdr.load.map_state = status1;
                        hdr.load.slot_state = slot;
                    }
                }

                if(add_0)
                {
                    hdr.load.value1 = value_01_add.execute(hdr.load.index);
                    hdr.load.value2 = value_02_add.execute(hdr.load.index);
                    hdr.load.value3 = value_03_add.execute(hdr.load.index);
                    hdr.load.value4 = value_04_add.execute(hdr.load.index);
                    hdr.load.value5 = value_05_add.execute(hdr.load.index);
                    hdr.load.value6 = value_06_add.execute(hdr.load.index);
                    hdr.load.value7 = value_07_add.execute(hdr.load.index);
                    hdr.load.value8 = value_08_add.execute(hdr.load.index);
                }
                else if(clr_0)
                {
                    value_01_clr.execute(hdr.load.index);
                    value_02_clr.execute(hdr.load.index);
                    value_03_clr.execute(hdr.load.index);
                    value_04_clr.execute(hdr.load.index);
                    value_05_clr.execute(hdr.load.index);
                    value_06_clr.execute(hdr.load.index);
                    value_07_clr.execute(hdr.load.index);
                    value_08_clr.execute(hdr.load.index);
                }

                if(add_1)
                {
                    hdr.load.value1 = value_11_add.execute(hdr.load.index);
                    hdr.load.value2 = value_12_add.execute(hdr.load.index);
                    hdr.load.value3 = value_13_add.execute(hdr.load.index);
                    hdr.load.value4 = value_14_add.execute(hdr.load.index);
                    hdr.load.value5 = value_15_add.execute(hdr.load.index);
                    hdr.load.value6 = value_16_add.execute(hdr.load.index);
                    hdr.load.value7 = value_17_add.execute(hdr.load.index);
                    hdr.load.value8 = value_18_add.execute(hdr.load.index);
                }
                else if(clr_1)
                {
                    value_11_clr.execute(hdr.load.index);
                    value_12_clr.execute(hdr.load.index);
                    value_13_clr.execute(hdr.load.index);
                    value_14_clr.execute(hdr.load.index);
                    value_15_clr.execute(hdr.load.index);
                    value_16_clr.execute(hdr.load.index);
                    value_17_clr.execute(hdr.load.index);
                    value_18_clr.execute(hdr.load.index);
                }
            }
        }
    }
}

/*********************  D E P A R S E R  ************************/

control IngressDeparser(packet_out                  pkt,
    /* User */
    inout my_ingress_headers_t                      hdr,
    in    my_ingress_metadata_t                     meta,
    /* Intrinsic */
    in    ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md)
{
    Checksum() ipv4_checksum;
    
    apply
    {
        hdr.ipv4.hdr_checksum = ipv4_checksum.update({
                hdr.ipv4.version,
                hdr.ipv4.ihl,
                hdr.ipv4.diffserv,
                hdr.ipv4.total_len,
                hdr.ipv4.identification,
                hdr.ipv4.flags,
                hdr.ipv4.frag_offset,
                hdr.ipv4.ttl,
                hdr.ipv4.protocol,
                hdr.ipv4.src_addr,
                hdr.ipv4.dst_addr
        });

        pkt.emit(hdr);
    }
}


/*************************************************************************
 ****************  E G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/

/***********************  H E A D E R S  ************************/

struct my_egress_headers_t
{
}

/********  G L O B A L   E G R E S S   M E T A D A T A  *********/

struct my_egress_metadata_t
{
}

/***********************  P A R S E R  **************************/

parser EgressParser(packet_in       pkt,
    /* User */
    out my_egress_headers_t         hdr,
    out my_egress_metadata_t        meta,
    /* Intrinsic */
    out egress_intrinsic_metadata_t eg_intr_md)
{
    state start
    {
        pkt.extract(eg_intr_md);
        transition accept;
    }
}

/***************** M A T C H - A C T I O N  *********************/

control Egress(
    /* User */
    inout my_egress_headers_t                         hdr,
    inout my_egress_metadata_t                        meta,
    /* Intrinsic */    
    in    egress_intrinsic_metadata_t                 eg_intr_md,
    in    egress_intrinsic_metadata_from_parser_t     eg_prsr_md,
    inout egress_intrinsic_metadata_for_deparser_t    eg_dprsr_md,
    inout egress_intrinsic_metadata_for_output_port_t eg_oport_md)
{
    apply
    {
    }
}

/*********************  D E P A R S E R  ************************/

control EgressDeparser(packet_out                  pkt,
    /* User */
    inout my_egress_headers_t                      hdr,
    in    my_egress_metadata_t                     meta,
    /* Intrinsic */
    in    egress_intrinsic_metadata_for_deparser_t eg_dprsr_md)
{
    apply
    {
        pkt.emit(hdr);
    }
}


/************ F I N A L   P A C K A G E ******************************/

Pipeline(
    IngressParser(),
    Ingress(),
    IngressDeparser(),
    EgressParser(),
    Egress(),
    EgressDeparser()
) pipe;

Switch(pipe) main;
