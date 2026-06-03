#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// creates a console and redirects output streams.
void CreateAndAttachConsole();

// converts utf16 text to utf8 text.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// gets utf8 command line arguments.
std::vector<std::string> GetCommandLineArguments();

#endif  // runner_utils_h_
