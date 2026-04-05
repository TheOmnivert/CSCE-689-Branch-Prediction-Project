#ifndef BRANCH_TAGE_H
#define BRANCH_TAGE_H

#include <array>
#include <vector>
#include <bitset>
#include "modules.h"

class tage : public champsim::modules::branch_predictor {
    static constexpr int NUM_TABLES = 4;
    static constexpr int BASE_TABLE_SIZE = 8192;
    static constexpr int TAGGED_TABLE_SIZE = 2048;
    static constexpr int MAX_HISTORY = 130;

    static constexpr std::array<int, NUM_TABLES> history_lengths = {5, 15, 44, 130};
    static constexpr std::array<int, NUM_TABLES> tag_widths = {8, 9, 10, 11};

    struct TaggedEntry {
        int8_t pred_counter = 0;
        uint8_t tag = 0;
        uint8_t u_bit = 0;
    };

    std::vector<int8_t> base_predictor;
    std::vector<std::vector<TaggedEntry>> tagged_tables;
    std::bitset<MAX_HISTORY> global_history;

    uint32_t fold_history(int length, int compressed_length);
    uint32_t get_index(uint64_t pc, int table_idx);
    uint8_t get_tag(uint64_t pc, int table_idx);

public:
    using branch_predictor::branch_predictor;

    void initialize_branch_predictor();
    bool predict_branch(champsim::address ip);
    void last_branch_result(champsim::address ip, champsim::address branch_target, bool taken, uint8_t branch_type);
};

#endif
