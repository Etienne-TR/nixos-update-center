cmake_minimum_required(VERSION 3.21)
project(update-center-ui LANGUAGES CXX)

set(APP_NAME "nixos-update-center" CACHE STRING "Nom du projet (meta.nix)")
set(APP_TITLE "Mises à jour" CACHE STRING "Nom affiché (meta.nix)")

find_package(Qt6 6.5 REQUIRED COMPONENTS Widgets Quick QuickControls2 Network)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(${APP_NAME}-ui
  src/main.cpp
  src/backend.cpp
  src/backend.h
)
target_compile_definitions(${APP_NAME}-ui PRIVATE
  APP_NAME="${APP_NAME}" APP_TITLE="${APP_TITLE}")

qt_add_qml_module(${APP_NAME}-ui
  URI UpdateCenter
  VERSION 1.0
  QML_FILES
    qml/Main.qml
    qml/PendingPage.qml
    qml/JournalPage.qml
    qml/GenerationsPage.qml
    qml/SettingsPage.qml
    qml/RunProgress.qml
    qml/InputRow.qml
    qml/MenuEntry.qml
    qml/LineMenu.qml
    qml/SegmentedToggle.qml
    qml/Tag.qml
    qml/IconAction.qml
    qml/Card.qml
    qml/MonoText.qml
)

target_link_libraries(${APP_NAME}-ui PRIVATE
  Qt6::Widgets Qt6::Quick Qt6::QuickControls2 Qt6::Network)

install(TARGETS ${APP_NAME}-ui RUNTIME DESTINATION bin)
