#include "seznec_tagesc_24kb.h"

#include "instruction.h"

#include "my_cond_branch_predictor.hpp"

int seznec_tagesc_24kb::cbp_branch_type(uint8_t branch_type)
{
  switch (branch_type) {
  case BRANCH_CONDITIONAL:
    return 1;
  case BRANCH_INDIRECT:
  case BRANCH_INDIRECT_CALL:
  case BRANCH_RETURN:
    return 2;
  default:
    return 0;
  }
}

void seznec_tagesc_24kb::initialize_branch_predictor() { cbp2025.setup(); }

bool seznec_tagesc_24kb::predict_branch(champsim::address ip, champsim::address predicted_target, bool always_taken, uint8_t branch_type)
{
  (void)predicted_target;

  if (branch_type != BRANCH_CONDITIONAL) {
    return always_taken;
  }

  pending_branch pending{};
  pending.seq_no = next_seq_no_++;
  pending.piece = 0;
  pending.prediction = cbp2025.predict(pending.seq_no, pending.piece, ip.to<uint64_t>());
  pending_conditional_branches_.push_back(pending);
  return pending.prediction;
}

void seznec_tagesc_24kb::last_branch_result(champsim::address ip, champsim::address branch_target, bool taken, uint8_t branch_type)
{
  const auto pc = ip.to<uint64_t>();
  const auto next_pc = branch_target.to<uint64_t>();
  const int brtype = cbp_branch_type(branch_type);

  if (branch_type == BRANCH_CONDITIONAL) {
    if (!pending_conditional_branches_.empty()) {
      const auto pending = pending_conditional_branches_.front();
      pending_conditional_branches_.pop_front();
      cbp2025.history_update(pending.seq_no, pending.piece, pc, brtype, taken, next_pc);
      cbp2025.update(pending.seq_no, pending.piece, pc, taken, pending.prediction, next_pc);
      return;
    }

    // Fallback if ChampSim calls update without a prior predict hook for this branch.
    const uint64_t seq_no = next_seq_no_++;
    constexpr uint8_t piece = 0;
    const bool prediction = cbp2025.predict(seq_no, piece, pc);
    cbp2025.history_update(seq_no, piece, pc, brtype, taken, next_pc);
    cbp2025.update(seq_no, piece, pc, taken, prediction, next_pc);
    return;
  }

  cbp2025.TrackOtherInst(pc, brtype, taken, next_pc);
}
