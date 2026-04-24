#ifndef BRANCH_JIMENEZ_MPP_384KB_H
#define BRANCH_JIMENEZ_MPP_384KB_H

#include <cstdint>
#include <deque>

#include "address.h"
#include "instruction.h"
#include "modules.h"

#include "cbp2016_tage_sc_l.h"
#include "my_cond_branch_predictor.h"

class jimenez_mpp_384kb : public champsim::modules::branch_predictor
{
public:
  using branch_predictor::branch_predictor;

  void initialize_branch_predictor()
  {
    cbp2016_tage_sc_l.setup();
    cond_predictor_impl.setup();
  }

  bool predict_branch(champsim::address ip, champsim::address predicted_target, bool always_taken, uint8_t branch_type)
  {
    (void)predicted_target;

    if (branch_type != BRANCH_CONDITIONAL) {
      return always_taken;
    }

    pending_branch pending{};
    pending.seq_no = next_seq_no_++;
    pending.piece = 0;

    const auto pc = ip.to<uint64_t>();
    const bool tage_sc_l_pred = cbp2016_tage_sc_l.predict(pending.seq_no, pending.piece, pc);
    pending.prediction = cond_predictor_impl.predict(pending.seq_no, pending.piece, pc, tage_sc_l_pred);

    pending_conditional_branches_.push_back(pending);
    return pending.prediction;
  }

  void last_branch_result(champsim::address ip, champsim::address branch_target, bool taken, uint8_t branch_type)
  {
    const auto pc = ip.to<uint64_t>();
    const auto next_pc = branch_target.to<uint64_t>();
    const int brtype = cbp_branch_type(branch_type);

    if (branch_type == BRANCH_CONDITIONAL) {
      pending_branch pending{};
      if (!pending_conditional_branches_.empty()) {
        pending = pending_conditional_branches_.front();
        pending_conditional_branches_.pop_front();
      } else {
        pending.seq_no = next_seq_no_++;
        pending.piece = 0;
        const bool tage_sc_l_pred = cbp2016_tage_sc_l.predict(pending.seq_no, pending.piece, pc);
        pending.prediction = cond_predictor_impl.predict(pending.seq_no, pending.piece, pc, tage_sc_l_pred);
      }

      cbp2016_tage_sc_l.history_update(pending.seq_no, pending.piece, pc, brtype, pending.prediction, taken, next_pc);
      cond_predictor_impl.history_update(pending.seq_no, pending.piece, pc, taken, next_pc);

      cbp2016_tage_sc_l.update(pending.seq_no, pending.piece, pc, taken, pending.prediction, next_pc);
      cond_predictor_impl.update(pending.seq_no, pending.piece, pc, taken, pending.prediction, next_pc);
      return;
    }

    constexpr bool pred_taken_nonconditional = true;
    cbp2016_tage_sc_l.TrackOtherInst(pc, brtype, pred_taken_nonconditional, taken, next_pc);
    cond_predictor_impl.nonconditional_history_update(next_seq_no_++, 0, pc, taken, next_pc, to_inst_class(branch_type));
  }

private:
  struct pending_branch {
    uint64_t seq_no = 0;
    uint8_t piece = 0;
    bool prediction = false;
  };

  static InstClass to_inst_class(uint8_t branch_type)
  {
    switch (branch_type) {
    case BRANCH_CONDITIONAL:
      return InstClass::condBranchInstClass;
    case BRANCH_INDIRECT:
      return InstClass::uncondIndirectBranchInstClass;
    case BRANCH_DIRECT_CALL:
      return InstClass::callDirectInstClass;
    case BRANCH_INDIRECT_CALL:
      return InstClass::callIndirectInstClass;
    case BRANCH_RETURN:
      return InstClass::ReturnInstClass;
    case BRANCH_DIRECT_JUMP:
    case BRANCH_OTHER:
    default:
      return InstClass::uncondDirectBranchInstClass;
    }
  }

  static int cbp_branch_type(uint8_t branch_type)
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

  uint64_t next_seq_no_ = 1;
  std::deque<pending_branch> pending_conditional_branches_;
};

#endif
