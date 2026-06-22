#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "updater.hpp"
#include "game/game.hpp"

#include <utils/flags.hpp>
#include <utils/progress_ui.hpp>
#include <updater/updater.hpp>

namespace updater {
namespace {
void remove_folder_if_exists(const std::filesystem::path &path,
                             const std::string &label) {
  std::error_code ec{};
  if (!std::filesystem::exists(path, ec)) {
    return;
  }

  std::filesystem::remove_all(path, ec);
  if (ec) {
    throw std::runtime_error("Failed to reset " + label + ": " +
                             path.string() + " (" + ec.message() + ")");
  }
}

void hard_reset_download_cache(const std::filesystem::path &appdata_path) {
  remove_folder_if_exists(appdata_path / "data", "updater data cache");
}

void mirror_downloaded_data_to_game_folder(
    const std::filesystem::path &appdata_path) {
  const auto source_data = appdata_path / "data";
  const auto game_data = game::get_game_path() / "data";

  std::error_code ec{};
  if (!std::filesystem::exists(source_data, ec)) {
    throw std::runtime_error("Updater did not download a data folder: " +
                             source_data.string());
  }

  // The game/client loads loose UI scripts from the game folder's data path.
  // Force that folder to match the freshly downloaded Swifly updater data so
  // old cached Lua files cannot keep winning.
  remove_folder_if_exists(game_data, "game data folder");

  std::filesystem::create_directories(game_data.parent_path(), ec);
  if (ec) {
    throw std::runtime_error("Failed to create game data parent folder: " +
                             game_data.parent_path().string() + " (" +
                             ec.message() + ")");
  }

  std::filesystem::copy(source_data, game_data,
                        std::filesystem::copy_options::recursive |
                            std::filesystem::copy_options::overwrite_existing,
                        ec);
  if (ec) {
    throw std::runtime_error("Failed to mirror Swifly data into game folder: " +
                             source_data.string() + " -> " +
                             game_data.string() + " (" + ec.message() + ")");
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
    hard_reset_download_cache(appdata_path);

    run(appdata_path);

    // Then force the actual BO3 folder's data folder to match the fresh
    // LocalAppData\\Swifly\\data folder. This prevents the game from loading
    // old loose scripts from the install directory.
    mirror_downloaded_data_to_game_folder(appdata_path);
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
