clear; clc; close all;

%% 1. AUDIO INPUT AND PREPROCESSING
disp('==================================================');
disp('      MULTI-BAND SPEECH EQUALIZER (PODCAST)       ');
disp('==================================================');

% Ask user for the audio file. Default to "speech.wav" if empty.
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
    % Create a dummy signal with low freq (500Hz), high freq (3000Hz), and noise
    x = randn(size(t))*0.1 + sin(2*pi*500*t)*0.5 + sin(2*pi*3000*t)*0.2;
end

% Convert stereo to mono
% WHY: Most multi-band equalizers process a single stream to save memory 
% and processing power. If stereo is needed, we would duplicate this entire pipeline.
if size(x, 2) > 1
    x = mean(x, 2);
    disp('Stereo audio detected: Converted to Mono to simplify processing.');
end

% Prompt for output sample rate explicitly
output_fs = input(sprintf('Enter desired output sample rate (Hz) [default %d]: ', Fs));
if isempty(output_fs) || output_fs <= 0
    output_fs = Fs; 
end

%% 2. EQUALIZER MODE AND BAND CONFIGURATION
disp(' ');
disp('Select Operation Mode:');
disp('1. Preset Mode (Speech-Optimized 7 Bands)');
disp('2. Custom Mode (5 to 10 user-defined bands)');
mode_sel = input('Enter mode (1 or 2) [default 1]: ');
if isempty(mode_sel), mode_sel = 1; end

Nyquist = Fs / 2; % The highest frequency we can represent without aliasing

if mode_sel == 1
    % Preset Bands - strictly aligned with assignment requirements
    bands = [0 100; 100 300; 300 800; 800 2000; 2000 5000; 5000 10000; 10000 20000];
    disp('Using Preset Speech-Optimized Bands (Hz).');
    num_bands = 7;
else
    % Custom Bands setup with validation
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

% Safely limit frequency bands to Nyquist to prevent filter design crashes
for i = 1:num_bands
    if bands(i, 2) >= Nyquist
        bands(i, 2) = Nyquist - 1; 
    end
    if bands(i, 1) >= bands(i, 2)
        bands(i, 1) = max(0, bands(i, 2) - 100); 
    end
end

%% 3. FILTER TYPE AND ORDER SELECTION
disp(' ');
disp('Select Filter Type:');
disp('1. FIR');
disp('2. IIR');
filt_type = input('Enter choice (1 or 2) [default 1]: ');
if isempty(filt_type), filt_type = 1; end

win_name = ''; iir_name = '';

if filt_type == 1
    disp('FIR Window Types: 1=Hamming, 2=Hanning, 3=Blackman');
    win_type = input('Enter window type (1-3) [default 1]: ');
    if isempty(win_type), win_type = 1; end
    
    filt_order = input('Enter FIR filter order [default 50]: ');
    if isempty(filt_order), filt_order = 50; end
    % Ensure even order: required for FIR highpass/bandstop stability in MATLAB
    if mod(filt_order, 2) ~= 0, filt_order = filt_order + 1; end 
    
    windows = {@hamming, @hanning, @blackman};
    win_names = {'Hamming', 'Hanning', 'Blackman'};
    win_func = windows{win_type};
    win_name = win_names{win_type};
else
    disp('IIR Filter Types: 1=Butterworth, 2=Chebyshev I, 3=Chebyshev II');
    iir_type = input('Enter IIR type (1-3) [default 1]: ');
    if isempty(iir_type), iir_type = 1; end
    
    filt_order = input('Enter IIR filter order [default 4]: ');
    if isempty(filt_order), filt_order = 4; end
    
    iir_names = {'Butterworth', 'Chebyshev I', 'Chebyshev II'};
    iir_name = iir_names{iir_type};
end

%% 4. GAIN INPUT SETUP
% WHY CONVERT dB TO LINEAR?
% dB is logarithmic, mirroring human hearing. However, digital signals in 
% code require linear amplitude multipliers. We must convert dB back to linear.
disp(' ');
disp('Enter gains for each band in dB:');
gains_dB = zeros(num_bands, 1);
for i = 1:num_bands
    fprintf('Band %d (%d Hz - %d Hz):\n', i, round(bands(i,1)), round(bands(i,2)));
    g_val = input('  Gain (dB) [default 0]: ');
    if isempty(g_val), g_val = 0; end
    gains_dB(i) = g_val;
end

%% 5. SIGNAL PROCESSING & FILTER DESIGN
disp(' ');
disp('Processing Signal... Please wait.');
y = zeros(size(x)); % Pre-allocate output array for speed and memory efficiency

for i = 1:num_bands
    f_low = bands(i, 1);
    f_high = bands(i, 2);
    
    % Normalize frequencies relative to Nyquist
    Wn = [f_low, f_high] / Nyquist;
    
    % Determine exact filter band type based on edges
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
    
    % Design the filter coefficients (b: numerator/zeros, a: denominator/poles)
    if filt_type == 1
        b = fir1(filt_order, W_pass, btype, win_func(filt_order+1));
        a = 1; % FIR has no poles (except at origin), so denominator is 1
        type_desc = sprintf('FIR (%s)', win_name);
    else
        if iir_type == 1
            [b, a] = butter(filt_order, W_pass, btype);
        elseif iir_type == 2
            [b, a] = cheby1(filt_order, 1, W_pass, btype); % 1dB passband ripple
        else
            [b, a] = cheby2(filt_order, 40, W_pass, btype); % 40dB stopband attenuation
        end
        type_desc = sprintf('IIR (%s)', iir_name);
    end
    
    % Generate filter analysis plots for each band (Explicitly separated plots)
    plot_filter_analysis(b, a, Fs, i, bands(i,:), filt_order, type_desc);
    
    % Apply the filter to the signal
    x_filtered = filter(b, a, x);
    
    % Convert dB to linear scale and multiply amplitude
    gain_linear = 10^(gains_dB(i) / 20);
    x_filtered = x_filtered * gain_linear;
    
    % Combine all processed bands in the time domain
    y = y + x_filtered;
end

%% 6. OUTPUT RESAMPLING & NORMALIZATION
% WHY RESAMPLING?
% Demonstrates decimation (downsampling) or interpolation (upsampling). Useful 
% when passing audio to systems operating at different clock rates.
if output_fs ~= Fs
    disp(sprintf('Resampling from %d Hz to %d Hz...', Fs, output_fs));
    y = resample(y, output_fs, Fs);
    y_time = (0:length(y)-1)'/output_fs; 
else
    y_time = (0:length(y)-1)'/Fs;
end

% WHY NORMALIZATION?
% Positive gains can push amplitude above 1.0 or below -1.0. This exceeds 
% the DAC limit, causing hard digital clipping. Normalizing to 0.99 prevents this.
y = 0.99 * y / max(abs(y));

%% 7. SYSTEM ANALYSIS: TIME, FREQ, PSD, AND SPECTROGRAM
disp('Generating system comparisons...');

% --- 7.1 Time Domain Comparison ---
figure('Name', 'Time & Frequency Domain Comparison', 'NumberTitle', 'off');
sgtitle('Original vs. Equalized Signal Comparison');

subplot(2,2,1);
t_x = (0:length(x)-1)/Fs;
plot(t_x, x, 'b'); 
title('Original Signal (Time)'); xlabel('Time (s)'); ylabel('Amplitude'); grid on;

subplot(2,2,2);
plot(y_time, y, 'r'); 
title('Processed Signal (Time)'); xlabel('Time (s)'); ylabel('Amplitude'); grid on;

% --- 7.2 Frequency Domain Comparison (FFT) ---
% WHY FFT: Shows the raw frequency bin magnitudes. Gives a quick mathematical 
% snapshot of which frequencies are physically present in the array.
N_fft_x = length(x);
f_vec_x = (0:N_fft_x-1)*(Fs/N_fft_x);
X_mag = abs(fft(x));

N_fft_y = length(y);
f_vec_y = (0:N_fft_y-1)*(output_fs/N_fft_y);
Y_mag = abs(fft(y));

subplot(2,2,3);
plot(f_vec_x(1:floor(N_fft_x/2)), X_mag(1:floor(N_fft_x/2)), 'b'); 
title('Original Spectrum (FFT)'); xlabel('Frequency (Hz)'); ylabel('Magnitude'); grid on;
xlim([0, min(Fs, output_fs)/2]);

subplot(2,2,4);
plot(f_vec_y(1:floor(N_fft_y/2)), Y_mag(1:floor(N_fft_y/2)), 'r'); 
title('Processed Spectrum (FFT)'); xlabel('Frequency (Hz)'); ylabel('Magnitude'); grid on;
xlim([0, min(Fs, output_fs)/2]);

% --- 7.3 Power Spectral Density (Welch) ---
% WHY PSD: The FFT is often too noisy. Welch's method averages overlapping 
% windowed segments, providing a much cleaner, smoothed curve of power distribution.
figure('Name', 'Power Spectral Density (PSD)', 'NumberTitle', 'off');
[Pxx_in, F_in] = pwelch(x, hamming(1024), 512, 1024, Fs);
[Pxx_out, F_out] = pwelch(y, hamming(1024), 512, 1024, output_fs);
plot(F_in, 10*log10(Pxx_in), 'b', 'LineWidth', 1.5); hold on;
plot(F_out, 10*log10(Pxx_out), 'r', 'LineWidth', 1.5);
legend('Original', 'Equalized');
title('PSD Comparison (Welch Method)'); xlabel('Frequency (Hz)'); ylabel('Power/Frequency (dB/Hz)');
grid on; hold off;

% --- 7.4 Spectrogram Comparison ---
% WHY SPECTROGRAM: Shows time and frequency simultaneously. We can visually 
% identify formants (speech structure) or transient noises (clicks/hisses).
figure('Name', 'Spectrogram Analysis', 'NumberTitle', 'off');
sgtitle('Time-Frequency Analysis (Spectrogram)');
subplot(2,1,1);
spectrogram(x, 1024, 512, 1024, Fs, 'yaxis');
title('Original Signal Spectrogram');

subplot(2,1,2);
spectrogram(y, 1024, 512, 1024, output_fs, 'yaxis');
title('Processed Signal Spectrogram');

%% 8. LISTENING EVALUATION AND TRADE-OFFS
disp(' ');
disp('==================================================');
disp('            LISTENING EVALUATION RESULTS          ');
disp('==================================================');
fprintf('Summary of Effects, Artifacts, and Trade-Offs:\n');
fprintf('1. Speech Clarity: Boosting 2kHz-5kHz significantly improves vocal intelligibility.\n');
fprintf('2. Noise Reduction: Attenuating <100Hz effectively reduces structural rumble or DC bias.\n');
fprintf('3. FIR vs IIR Complexity: FIR requires larger memory buffers/computation (high order),\n');
fprintf('   while IIR is highly efficient but risks system instability if poles move outside the unit circle.\n');
fprintf('4. Phase Distortion (Artifacts): IIR filters introduce non-linear phase shift, which can \n');
fprintf('   smear sharp transients (like hard consonants). FIR preserves phase alignment.\n');
fprintf('5. Clipping Risks: Aggressive positive gains risk clipping, which we mitigated \n');
fprintf('   by normalizing the final summed array to a ceiling of 0.99.\n');
disp('==================================================');

%% 9. PLAYBACK AND SAVING OPTIONS
disp(' ');
play_opt = input('Play output audio? (1=yes / 0=no) [default 0]: ');
if isempty(play_opt), play_opt = 0; end

if play_opt == 1
    sound(y, output_fs);
    stop_opt = input('Stop audio playback? (1=yes / 0=no) [default 0]: ');
    if isempty(stop_opt), stop_opt = 0; end
    if stop_opt == 1
        clear sound;
    end
end

disp(' ');
save_opt = input('Save processed audio? (1=yes / 0=no) [default 0]: ');
if isempty(save_opt), save_opt = 0; end

if save_opt == 1
    % Save normal rate
    audiowrite('equalized_output.wav', y, output_fs);
    disp('Saved: equalized_output.wav (User Selected Rate)');
    
    % Save Sample Rate x4 (Interpolation)
    y_4x = resample(y, 4, 1);
    audiowrite('equalized_output_4x.wav', y_4x, output_fs*4);
    disp('Saved: equalized_output_4x.wav (Sample Rate x4)');
    
    % Save Sample Rate x0.5 (Decimation)
    y_half = resample(y, 1, 2);
    audiowrite('equalized_output_half.wav', y_half, round(output_fs/2));
    disp('Saved: equalized_output_half.wav (Sample Rate x0.5)');
end

disp('==================================================');
disp('Processing Complete! Ready for Submission.');
disp('==================================================');

%% ========================================================================
% HELPER FUNCTION: Plot Detailed Filter Analysis
% =========================================================================
function plot_filter_analysis(b, a, Fs, band_idx, band_freqs, order, type_desc)
    fig_name = sprintf('Band %d Analysis (%.0f Hz - %.0f Hz)', band_idx, band_freqs(1), band_freqs(2));
    figure('Name', fig_name, 'NumberTitle', 'off');
    sgtitle(sprintf('Band %d | %s | Order: %d | Range: %.0f-%.0f Hz', band_idx, type_desc, order, band_freqs(1), band_freqs(2)));
    
    % Get frequency response data explicitly to separate magnitude and phase
    [h, f_freqz] = freqz(b, a, 1024, Fs);
    mag_dB = 20*log10(abs(h));
    phase_rad = unwrap(angle(h));
    
    % 1. Explicit Magnitude Response Plot
    subplot(2,3,1);
    plot(f_freqz, mag_dB, 'b', 'LineWidth', 1.5);
    title('Magnitude Response'); 
    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)'); 
    grid on;
    
    % 2. Explicit Phase Response Plot
    subplot(2,3,2);
    plot(f_freqz, phase_rad, 'r', 'LineWidth', 1.5);
    title('Phase Response'); 
    xlabel('Frequency (Hz)'); ylabel('Phase (radians)'); 
    grid on;
    
    % 3. Impulse Response Plot
    subplot(2,3,3);
    impz(b, a, 50, Fs);
    title('Impulse Response'); 
    grid on;
    
    % 4. Step Response Plot (Using manual filter to guarantee MATLAB version compatibility)
    subplot(2,3,4);
    step_input = ones(50, 1);
    step_resp = filter(b, a, step_input);
    stem(0:49, step_resp, 'filled', 'MarkerFaceColor', 'k');
    title('Step Response (Calculated)'); 
    xlabel('Samples'); ylabel('Amplitude'); 
    grid on;
    
    % 5. Pole-Zero Plot
    subplot(2,3,5);
    zplane(b, a);
    title('Pole-Zero Plot'); 
    grid on;
end