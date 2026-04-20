#ifndef BRANCH_SEZNEC_TAGESC_1536KB_H
#define BRANCH_SEZNEC_TAGESC_1536KB_H

#include <cstdint>
#include <deque>

#include "address.h"
#include "modules.h"

class seznec_tagesc_1536kb : public champsim::modules::branch_predictor
{
public:
  using branch_predictor::branch_predictor;

  void initialize_branch_predictor();
  bool predict_branch(champsim::address ip, champsim::address predicted_target, bool always_taken, uint8_t branch_type);
  void last_branch_result(champsim::address ip, champsim::address branch_target, bool taken, uint8_t branch_type);

private:
  struct pending_branch {
    uint64_t seq_no = 0;
    uint8_t piece = 0;
    bool prediction = false;
  };

  static int cbp_branch_type(uint8_t branch_type);

  uint64_t next_seq_no_ = 1;
  std::deque<pending_branch> pending_conditional_branches_;
};

#endif
