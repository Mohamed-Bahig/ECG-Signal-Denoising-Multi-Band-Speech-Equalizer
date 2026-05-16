[ecg, fs, tm] = rdsamp('100');

%choose first ECG channel
x = ecg(:,1);
duration = 20;
N = duration * fs;

x_in = x(1:N);
t = (0:N-1)/fs;
% High pass cheby1 filter
rp=0.2;
[b_hpf, a_hpf] = cheby1(4,rp, 0.5/(fs/2), 'high');

% 50 Hz Notch filter
fnorm = 50/(fs/2);
Q = 40;
bw = fnorm/Q;
[b_notch, a_notch] = iirnotch(fnorm, bw);

% Low-pass cheby1 filter
[b_lpf, a_lpf] = cheby1(4,rp,100/(fs/2), 'low');

y1 = filtfilt(b_hpf, a_hpf, x_in);
y2 = filtfilt(b_notch, a_notch, y1);
y3 = filtfilt(b_lpf, a_lpf, y2);

figure;
plot(t, x_in);
hold on;
plot(t, y3);
xlabel('Time in s');
ylabel('Amplitude in mV');
title('Original vs Cheby1 Filtered ECG');
legend('Original ECG', 'Filtered ECG');
grid on;


%Magnitude and phase response
figure;
freqz(b_hpf, a_hpf, 4096, fs);
title('cheby1 of High pass Filter Frequency Response');

figure;
freqz(b_notch, a_notch, 4096, fs);
title('50 Hz Notch Filter Frequency Response');

figure;
freqz(b_lpf, a_lpf, 4096, fs);
title('Cheby1 Low pass of Filter Frequency Response');

%Impulse response
N_sample = 4096;
t_sample = (0:N_sample-1)/fs;

h_hpf = impz(b_hpf, a_hpf, N_sample);
figure;
plot(t_sample, h_hpf);
grid on;
xlabel('Time in s');
ylabel('Amplitude');
title('Impulse Response - Cheby1 High pass filter');

h_notch = impz(b_notch, a_notch, N_sample);
figure;
plot(t_sample, h_notch);
grid on;
xlabel('Time in s');
ylabel('Amplitude');
title('Impulse Response - 50 Hz of Notch Filter');

h_lpf = impz(b_lpf, a_lpf, N_sample);
figure;
plot(t_sample, h_lpf);
grid on;
xlabel('Time in s');
ylabel('Amplitude');
title('Impulse Response - Cheby1 Low pass filter');

% Step Responses
s_hp = stepz(b_hpf, a_hpf, N_sample);
figure;
plot(t_sample, s_hp);
grid on;
xlabel('Time in s');
ylabel('Amplitude');
title('Step Response of Cheby1 High pass filter');

s_notch = stepz(b_notch, a_notch, N_sample);
figure;
plot(t_sample, s_notch);
grid on;
xlabel('Time in s');
ylabel('Amplitude');
title('Step Response of 50 Hz Notch Filter');

s_lp = stepz(b_lpf, a_lpf, N_sample);
figure;
plot(t_sample, s_lp);
grid on;
xlabel('Time (s)');
ylabel('Amplitude');
title('Step Response - Cheby1 Low pass filter');

% Pole-Zero Plots
figure;
zplane(b_hpf, a_hpf);
title('Pole-Zero Plot - Cheby1 High pass filter');

figure;
zplane(b_notch, a_notch);
title('Pole-Zero Plot - 50 Hz Notch Filter');

figure;
zplane(b_lpf, a_lpf);
title('Pole-Zero Plot - Cheby1 Low pass filter');

%display coefficients of numerator and denominator of Butterworth

disp('Cheby1 High-pass numerator coefficient b_hpf:');
disp(b_hpf);

disp('Cheby1 High pass filter denominator coefficient of a_hpf:');
disp(a_hpf);

disp('50 Hz Notch filter numerator coefficient of b_notch:');
disp(b_notch);

disp('50 Hz Notch denominator coefficient of a_notch:');
disp(a_notch);

disp('Cheby1 Low-pass numerator coefficient of b_lpf:');
disp(b_lpf);

disp('Cheby1 Low-pass denominator coefficient of a_lpf:');
disp(a_lpf);


% pwelch
[pwelch_orig, f_psd] = pwelch(x_in, hamming(2048), 1024, 4096, fs);
[pwelch_filtered, f_psd] = pwelch(y3, hamming(2048), 1024, 4096, fs);

figure;
plot(f_psd, 10*log10(pwelch_orig));
hold on;
plot(f_psd, 10*log10(pwelch_filtered));
grid on;
xlabel('Frequency Hz');
ylabel('Power/Frequency dB/Hz');
title('PSD Comparison: Original vs Filtered ECG');
xlim([0 180]);

% Spectrogram using STFT 
figure;
spectrogram(x_in, hamming(2048), 1024, 4096, fs, 'yaxis');
title('Spectrogram of Original ECG');

figure;
spectrogram(y3, hamming(2048), 1024, 4096, fs, 'yaxis');
title('Spectrogram of Filtered ECG');

% SNR Improvement
noise = x_in - y3;
SNR= 10*log10(sum(y3.^2) / sum(noise.^2));
fprintf('SNR : %.2f dB\n', SNR);

% 5) Distortion observation
figure;
plot(t, noise);
grid on;
xlabel('Time in s');
ylabel('Amplitude mV');
title('Removed Noise');