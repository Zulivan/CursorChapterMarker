#pragma once

#include <obs-module.h>
#include <obs-frontend-api.h>

#include <QDialog>
#include <QLabel>
#include <QLineEdit>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QString>
#include <mutex>
#include <string>

#define DEFAULT_PRESS_FORMAT   "+ Cursor X:%X Y:%Y"
#define DEFAULT_RELEASE_FORMAT "- Cursor X:%X Y:%Y"

// Thread-safe format string cache read by hotkey callbacks without touching Qt.
struct FormatCache {
	std::mutex  mtx;
	std::string press   = DEFAULT_PRESS_FORMAT;
	std::string release = DEFAULT_RELEASE_FORMAT;

	std::string getPress()   { std::lock_guard<std::mutex> lg(mtx); return press; }
	std::string getRelease() { std::lock_guard<std::mutex> lg(mtx); return release; }
	void set(const std::string &p, const std::string &r) {
		std::lock_guard<std::mutex> lg(mtx);
		press = p; release = r;
	}
};

extern FormatCache g_formats;

class CursorChapterSettings : public QDialog {
	Q_OBJECT

public:
	explicit CursorChapterSettings(QWidget *parent = nullptr);

	void LoadSettings(obs_data_t *data);
	void SaveSettings(obs_data_t *data) const;

private slots:
	void onAccepted();

private:
	QLineEdit *pressFormatEdit;
	QLineEdit *releaseFormatEdit;
};
