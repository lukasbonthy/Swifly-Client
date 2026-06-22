#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "updater.hpp"
#include "game/game.hpp"

#include <utils/flags.hpp>
#include <utils/progress_ui.hpp>
#include <updater/updater.hpp>

namespace updater {
namespace {
void hard_reset_data_folder(const std::filesystem::path &appdata_path) {
  const auto data_path = appdata_path / "data";

  std::error_code ec{};
  if (!std::filesystem::exists(data_path, ec)) {
    return;
  }

  std::filesystem::remove_all(data_path, ec);
  if (ec) {
    throw std::runtime_error("Failed to reset updater data folder: " +
                             data_path.string() + " (" + ec.message() + ")");
  }
}
} // namespace

void update() {
  if (utils::flags::has_flag("noupdate")) {
    return;
  }

  try {
    const auto appdata_path = game::get_appdata_path();

    // Force the updater to stop reusing old downloaded UI files.
    // This wipes LocalAppData\\Swifly\\data before every update check so the
    // launcher has to pull the current files from the update host/manifest.
    hard_reset_data_folder(appdata_path);

    run(appdata_path);
  } catch (update_cancelled &) {
    TerminateProcess(GetCurrentProcess(), 0);
  } catch (const std::exception &e) {
    utils::progress_ui::show_error("Updater Error", e.what());
  } catch (...) {
    utils::progress_ui::show_error("Updater Error",
                                   "Unknown error occurred during update.");
  }
}

class component final : public generic_component {
public:
  component() {
    this->update_thread_ = std::thread([] { update(); });
  }

  void pre_destroy() override { join(); }

  void post_unpack() override { join(); }

  component_priority priority() const override {
    return component_priority::updater;
  }

private:
  std::thread update_thread_{};

  void join() {
    if (this->update_thread_.joinable()) {
      this->update_thread_.join();
    }
  }
};
} // namespace updater

REGISTER_COMPONENT(updater::component)
