#include "stdafx.h"

using namespace MT32Emu;

static const ControlROMFeatureSet MT32_COMPATIBLE(true, true);
static const ControlROMFeatureSet CM32L_COMPATIBLE(false, false);

int main(int argc, char *argv[]) {
	Analog *analog = new Analog(AnalogOutputMode_ACCURATE, &MT32_COMPATIBLE);
	analog->setSynthOutputGain(1.0f);
	int i = 0;
	do {
		Sample inLeft = 0;
		if (analog->getDACStreamsLength(1) > 0) std::cin >> inLeft;
		Sample silence = 0;
		Sample outStream[2];
		Sample *outP = outStream;
		analog->process(&outP, &inLeft, &silence, &silence, &silence, &silence, &silence, 1);
#if MT32EMU_USE_FLOAT_SAMPLES
		printf("%.16e\n", outStream[0]);
#else
		printf("%d\n", outStream[0]);
#endif
	} while (!std::cin.eof() && (i++ < 65535));
	return 0;
}
