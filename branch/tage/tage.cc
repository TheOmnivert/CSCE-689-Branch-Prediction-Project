#include "tage.h"

void tage::initialize_branch_predictor() {
    base_predictor.assign(BASE_TABLE_SIZE, 0);
    tagged_tables.resize(NUM_TABLES, std::vector<TaggedEntry>(TAGGED_TABLE_SIZE));
    global_history.reset();
}

uint32_t tage::fold_history(int length, int compressed_length) {
    uint32_t hash = 0;
    for (int i = 0; i < length; i++) {
        if (global_history[i]) {
            hash ^= (1 << (i % compressed_length));
        }
    }
    return hash;
}

uint32_t tage::get_index(uint64_t pc, int table_idx) {
    uint32_t pc_hash = pc ^ (pc >> 2);
    uint32_t hist_hash = fold_history(history_lengths[table_idx], 11);
    return (pc_hash ^ hist_hash) % TAGGED_TABLE_SIZE;
}

uint8_t tage::get_tag(uint64_t pc, int table_idx) {
    uint32_t pc_hash = pc ^ (pc >> 4);
    uint32_t hist_hash = fold_history(history_lengths[table_idx], tag_widths[table_idx]);
    return (pc_hash ^ hist_hash) & ((1 << tag_widths[table_idx]) - 1);
}

bool tage::predict_branch(champsim::address ip_addr) {
    uint64_t ip = ip_addr.to<uint64_t>();
    bool prediction = base_predictor[ip % BASE_TABLE_SIZE] >= 0;

    for (int i = NUM_TABLES - 1; i >= 0; i--) {
        uint32_t index = get_index(ip, i);
        uint8_t tag = get_tag(ip, i);

        if (tagged_tables[i][index].tag == tag) {
            prediction = tagged_tables[i][index].pred_counter >= 0;
            break;
        }
    }
    return prediction;
}

void tage::last_branch_result(champsim::address ip_addr, champsim::address branch_target, bool taken, uint8_t branch_type) {
    uint64_t ip = ip_addr.to<uint64_t>();
    int provider_idx = -1;
    int alt_idx = -1;
    bool provider_pred = base_predictor[ip % BASE_TABLE_SIZE] >= 0;
    bool alt_pred = provider_pred;

    for (int i = NUM_TABLES - 1; i >= 0; i--) {
        uint32_t index = get_index(ip, i);
        uint8_t tag = get_tag(ip, i);

        if (tagged_tables[i][index].tag == tag) {
            if (provider_idx == -1) {
                provider_idx = i;
                provider_pred = tagged_tables[i][index].pred_counter >= 0;
            } else if (alt_idx == -1) {
                alt_idx = i;
                alt_pred = tagged_tables[i][index].pred_counter >= 0;
                break;
            }
        }
    }

    bool final_pred = (provider_idx != -1) ? provider_pred : alt_pred;

    if (provider_idx != -1 && provider_pred != alt_pred) {
        uint32_t index = get_index(ip, provider_idx);
        if (provider_pred == taken && tagged_tables[provider_idx][index].u_bit < 3) {
            tagged_tables[provider_idx][index].u_bit++;
        } else if (provider_pred != taken && tagged_tables[provider_idx][index].u_bit > 0) {
            tagged_tables[provider_idx][index].u_bit--;
        }
    }

    if (provider_idx != -1) {
        uint32_t index = get_index(ip, provider_idx);
        if (taken && tagged_tables[provider_idx][index].pred_counter < 3) {
            tagged_tables[provider_idx][index].pred_counter++;
        } else if (!taken && tagged_tables[provider_idx][index].pred_counter > -4) {
            tagged_tables[provider_idx][index].pred_counter--;
        }
    } else {
        uint32_t base_idx = ip % BASE_TABLE_SIZE;
        if (taken && base_predictor[base_idx] < 1) base_predictor[base_idx]++;
        else if (!taken && base_predictor[base_idx] > -2) base_predictor[base_idx]--;
    }

    if (final_pred != taken && provider_idx < NUM_TABLES - 1) {
        bool allocated = false;
        for (int i = provider_idx + 1; i < NUM_TABLES; i++) {
            uint32_t index = get_index(ip, i);
            if (tagged_tables[i][index].u_bit == 0) {
                tagged_tables[i][index].tag = get_tag(ip, i);
                tagged_tables[i][index].pred_counter = taken ? 0 : -1;
                allocated = true;
                break;
            }
        }
        if (!allocated) {
            for (int i = provider_idx + 1; i < NUM_TABLES; i++) {
                uint32_t index = get_index(ip, i);
                if (tagged_tables[i][index].u_bit > 0) tagged_tables[i][index].u_bit--;
            }
        }
    }

    global_history <<= 1;
    global_history[0] = taken;
}
