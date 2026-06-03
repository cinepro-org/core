#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// high dpi aware win32 window base.
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // creates a scaled window on the default monitor.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // shows the current window.
  bool Show();

  // releases os resources for the window.
  void Destroy();

  // inserts flutter content into the window tree.
  void SetChildContent(HWND content);

  // returns the backing window handle.
  HWND GetHandle();

  // sets whether closing the window quits the app.
  void SetQuitOnClose(bool quit_on_close);

  // returns the current client area.
  RECT GetClientArea();

 protected:
  // routes native window messages.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // runs subclass setup after creation.
  virtual bool OnCreate();

  // runs subclass cleanup during destroy.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // handles native message pump callbacks.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // retrieves the class instance for a window handle.
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // updates the frame theme to match the system.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // runner_win32_window_h_
