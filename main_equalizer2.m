
clear; clc; close all;

%% 1. Audio Input and Preprocessing
disp('==================================================');
disp('      MULTI-BAND SPEECH EQUALIZER (PODCAST)       ');
disp('==================================================');

% Audio file input
audio_file = input('Enter audio file name [default "speech.wav"]: ', 's');
if isempty(audio_file)
    audio_file = 'speech.wav';
end

try
    [x, Fs] = audioread(audio_file);
catch
    disp('Error: File not found. Generating sample 5-second noise/tone for demonstration...');
    Fs = 44100;
    t = (0:5*Fs-1)'/Fs;
    x = randn(size(t))*0.1 + sin(2*pi*500*t)*0.5 + sin(2*pi*3000*t)*0.2;
end

% Convert stereo to mono if needed
if size(x, 2) > 1
    x = mean(x, 2);
    disp('Stereo audio detected: Converted to Mono.');
end

%% 2. Equalizer Mode and Band Configuration
disp(' ');
disp('Select Operation Mode:');
disp('1. Preset Mode (Speech-Optimized 7 Bands)');
disp('2. Custom Mode (5 to 10 user-defined bands)');
mode_sel = input('Enter mode (1 or 2) [default 1]: ');
if isempty(mode_sel), mode_sel = 1; end

Nyquist = Fs / 2;

if mode_sel == 1
    % Preset Bands
    bands = [0 100; 100 300; 300 800; 800 2000; 2000 5000; 5000 10000; 10000 20000];
    disp('Using Preset Speech-Optimized Bands (Hz).');
else
    % Custom Bands
    num_bands = input('Enter number of bands (5 to 10) [default 5]: ');
    if isempty(num_bands) || num_bands < 5 || num_bands > 10
        num_bands = 5; 
        disp('Defaulting to 5 bands.');
    end
    
    bands = zeros(num_bands, 2);
    disp('Define frequency edges for each band. (First must start at 0, Last must end at 20000)');
    for i = 1:num_bands
        fprintf('Band %d:\n', i);
        if i == 1
            f_low = 0;
            disp('  Start Frequency: 0 Hz (Enforced)');
        else
            f_low = input(sprintf('  Start Frequency (Hz) [default %d]: ', bands(i-1, 2)));
            if isempty(f_low), f_low = bands(i-1, 2); end
        end
        
        if i == num_bands
            f_high = 20000;
            disp('  End Frequency: 20000 Hz (Enforced)');
        else
            f_high = input('  End Frequency (Hz) [default f_low + 1000]: ');
            if isempty(f_high), f_high = f_low + 1000; end
        end
        bands(i, :) = [f_low, f_high];
    end
end

% Safety check: Cap frequencies at Nyquist limit to prevent errors
bands(bands > Nyquist-1) = Nyquist - 1;
valid_idx = bands(:,1) < bands(:,2);
bands = bands(valid_idx, :); 
num_bands = size(bands, 1);

%% 3. Filter Type and Order Selection
disp(' ');
disp('Select Filter Type:');
disp('1. FIR');
disp('2. IIR');
filt_type = input('Enter choice (1 or 2) [default 1]: ');
if isempty(filt_type), filt_type = 1; end

if filt_type == 1
    disp('FIR Window Types: 1=Hamming, 2=Hanning, 3=Blackman');
    win_type = input('Enter window type (1-3) [default 1]: ');
    if isempty(win_type), win_type = 1; end
    
    filt_order = input('Enter FIR filter order [default 50]: ');
    if isempty(filt_order), filt_order = 50; end
    % Ensure even order for FIR highpass/bandstop stability
    if mod(filt_order, 2) ~= 0, filt_order = filt_order + 1; end 
else
    disp('IIR Filter Types: 1=Butterworth, 2=Chebyshev I, 3=Chebyshev II');
    iir_type = input('Enter IIR type (1-3) [default 1]: ');
    if isempty(iir_type), iir_type = 1; end
    
    filt_order = input('Enter IIR filter order [default 4]: ');
    if isempty(filt_order), filt_order = 4; end
end

%% 4. Gain Input Setup
disp(' ');
disp('Enter gains for each band in dB:');
gains_dB = zeros(num_bands, 1);
for i = 1:num_bands
    fprintf('Band %d (%d Hz - %d Hz):\n', i, round(bands(i,1)), round(bands(i,2)));
    g_val = input('  Gain (dB) [default 0]: ');
    if isempty(g_val), g_val = 0; end
    gains_dB(i) = g_val;
end

%% 5. Signal Processing & Filter Design
disp(' ');
disp('Processing Signal... Please wait.');
y = zeros(size(x)); % Pre-allocate output

for i = 1:num_bands
    f_low = bands(i, 1);
    f_high = bands(i, 2);
    
    % Normalize frequencies
    Wn = [f_low, f_high] / Nyquist;
    
    % Determine band type
    if f_low == 0
        btype = 'low';
        W_pass = Wn(2);
    elseif f_high >= Nyquist - 1
        btype = 'high';
        W_pass = Wn(1);
    else
        btype = 'bandpass';
        W_pass = Wn;
    end
    
    % Design Filter
    if filt_type == 1
        % FIR
        windows = {@hamming, @hann, @blackman};
        win_func = windows{win_type};
        b = fir1(filt_order, W_pass, btype, win_func(filt_order+1));
        a = 1;
    else
        % IIR
        if iir_type == 1
            [b, a] = butter(filt_order, W_pass, btype);
        elseif iir_type == 2
            [b, a] = cheby1(filt_order, 1, W_pass, btype); % 1dB ripple
        else
            [b, a] = cheby2(filt_order, 40, W_pass, btype); % 40dB stopband
        end
    end
    
    % Filter Analysis Plots
    plot_filter_analysis(b, a, Fs, i, bands(i,:), filt_order, filt_type);
    
    % Filter the signal
    x_filtered = filter(b, a, x);
    
    % Apply Gain (Linear scale)
    gain_linear = 10^(gains_dB(i) / 20);
    x_filtered = x_filtered * gain_linear;
    
    % Combine in time domain
    y = y + x_filtered;
end

% Normalize Output Audio to prevent clipping
y = 0.99 * y / max(abs(y));

%% 6. System Analysis: Time, Freq, PSD, and Spectrogram
disp('Generating system comparisons...');

% 6.1 Time Domain Comparison
figure('Name', 'Time & Freq Domain Comparison', 'NumberTitle', 'off');
subplot(2,2,1);
t_vec = (0:length(x)-1)/Fs;
plot(t_vec, x); title('Original Signal (Time)'); xlabel('Time (s)'); ylabel('Amplitude');

subplot(2,2,2);
plot(t_vec, y); title('Processed Signal (Time)'); xlabel('Time (s)'); ylabel('Amplitude');

% 6.2 Frequency Domain Comparison (FFT)
N_fft = length(x);
f_vec = (0:N_fft-1)*(Fs/N_fft);
X_mag = abs(fft(x));
Y_mag = abs(fft(y));

subplot(2,2,3);
plot(f_vec(1:floor(N_fft/2)), X_mag(1:floor(N_fft/2))); 
title('Original Signal (Frequency)'); xlabel('Frequency (Hz)'); ylabel('Magnitude');

subplot(2,2,4);
plot(f_vec(1:floor(N_fft/2)), Y_mag(1:floor(N_fft/2))); 
title('Processed Signal (Frequency)'); xlabel('Frequency (Hz)'); ylabel('Magnitude');

% 6.3 Power Spectral Density (Welch)
figure('Name', 'Power Spectral Density (PSD)', 'NumberTitle', 'off');
[Pxx_in, F_in] = pwelch(x, hamming(1024), 512, 1024, Fs);
[Pxx_out, F_out] = pwelch(y, hamming(1024), 512, 1024, Fs);
plot(F_in, 10*log10(Pxx_in), 'b', F_out, 10*log10(Pxx_out), 'r');
legend('Original', 'Equalized');
title('PSD Comparison (Welch Method)'); xlabel('Frequency (Hz)'); ylabel('Power/Frequency (dB/Hz)');
grid on;

% 6.4 Spectrogram Comparison
figure('Name', 'Spectrograms', 'NumberTitle', 'off');
subplot(2,1,1);
spectrogram(x, 1024, 512, 1024, Fs, 'yaxis');
title('Original Spectrogram');
subplot(2,1,2);
spectrogram(y, 1024, 512, 1024, Fs, 'yaxis');
title('Processed Spectrogram');

%% 7. Playback and Saving Options
disp(' ');
play_opt = input('Play output audio? (1=yes / 0=no) [default 0]: ');
if isempty(play_opt), play_opt = 0; end

if play_opt == 1
    sound(y, Fs);
    stop_opt = input('Stop audio playback? (1=yes / 0=no) [default 0]: ');
    if stop_opt == 1
        clear sound;
    end
end

disp(' ');
save_opt = input('Save processed audio? (1=yes / 0=no) [default 0]: ');
if isempty(save_opt), save_opt = 0; end

if save_opt == 1
    % Normal rate
    audiowrite('equalized_output.wav', y, Fs);
    disp('Saved: equalized_output.wav (Normal Rate)');
    
    % Multiplied by 4 (Interpolation)
    y_4x = resample(y, 4, 1);
    audiowrite('equalized_output_4x.wav', y_4x, Fs*4);
    disp('Saved: equalized_output_4x.wav (Sample Rate x4)');
    
    % Reduced to half (Decimation)
    y_half = resample(y, 1, 2);
    audiowrite('equalized_output_half.wav', y_half, round(Fs/2));
    disp('Saved: equalized_output_half.wav (Sample Rate x0.5)');
end

disp('==================================================');
disp('Processing Complete!');
disp('==================================================');

%% ========================================================================
% HELPER FUNCTION: Plot Filter Analysis
% =========================================================================
function plot_filter_analysis(b, a, Fs, band_idx, band_freqs, order, f_type)
    fig_name = sprintf('Band %d Analysis (%.0f Hz - %.0f Hz)', band_idx, band_freqs(1), band_freqs(2));
    figure('Name', fig_name, 'NumberTitle', 'off');
    
    % 1. Magnitude and Phase Response
    subplot(2,2,1);
    freqz(b, a, 1024, Fs);
    title('Magnitude & Phase Response');
    
    % 2. Impulse Response
    subplot(2,2,2);
    impz(b, a, 50, Fs);
    title('Impulse Response');
    
    % 3. Step Response
    subplot(2,2,3);
    stepz(b, a, 50, Fs);
    title('Step Response');
    
    % 4. Pole-Zero Plot
    subplot(2,2,4);
    zplane(b, a);
    if f_type == 1
        title(sprintf('Pole-Zero Plot (FIR, Order: %d)', order));
    else
        title(sprintf('Pole-Zero Plot (IIR, Order: %d)', order));
    end
end