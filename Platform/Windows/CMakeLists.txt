if(WIN32)
  add_library(fy_tsf SHARED TSF/FengYuTextService.cpp TSF/FengYuResources.rc TSF/FengYuTextService.def TSF/WindowsKeyMapper.cpp CandidateWindow/CandidateWindow.cpp Settings/CustomPhraseEditor.cpp Settings/CustomPhraseStore.cpp Settings/SettingsStore.cpp)
  target_include_directories(fy_tsf PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../../Core/include)
  target_link_libraries(fy_tsf PRIVATE fy_engine ole32 oleaut32 user32 gdi32 comctl32 comdlg32 uuid)
  set_target_properties(fy_tsf PROPERTIES OUTPUT_NAME "fy_tsf")
  add_custom_command(TARGET fy_tsf POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      $<TARGET_FILE:fy_engine>
      $<TARGET_FILE_DIR:fy_tsf>
  )

  add_executable(fy_tsf_factory_test TSF/FengYuComFactoryTest.cpp)
  target_link_libraries(fy_tsf_factory_test PRIVATE ole32 oleaut32 uuid)
  add_dependencies(fy_tsf_factory_test fy_tsf)
  add_test(NAME tsf_factory COMMAND fy_tsf_factory_test)
  set_tests_properties(tsf_factory PROPERTIES
    WORKING_DIRECTORY "$<TARGET_FILE_DIR:fy_tsf_factory_test>")

  add_executable(fy_windows_key_mapper_test TSF/WindowsKeyMapper.cpp TSF/WindowsKeyMapperTest.cpp)
  add_test(NAME windows_key_mapper COMMAND fy_windows_key_mapper_test)

  add_executable(fy_custom_phrase_store_test Settings/CustomPhraseStore.cpp Settings/CustomPhraseStoreTest.cpp)
  add_test(NAME custom_phrase_store COMMAND fy_custom_phrase_store_test)

  # The registration helper is invoked several times by Windows Installer.
  # Build it as a GUI-subsystem executable so those background custom actions
  # never flash console windows during install, upgrade, or uninstall.
  add_executable(fy_tsf_registration WIN32 TSF/TsfRegistration.cpp)
  target_link_libraries(fy_tsf_registration PRIVATE ole32 advapi32 shell32 uuid)
endif()
