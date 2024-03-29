function [  ] = livetest(  )
%LIVETEST Summary of this function goes here

% Set for how long the live processing should last
endTime = 10;
% And how many samples per channel should be acquired and processed at each
% iteration
audioFrameLength = 3200;

AudioInput = dsp.AudioRecorder;
fs = AudioInput.SampleRate;

micPositions = [-0.05, 0.05];
micPairs = [1 2];
numPairs = size(micPairs, 1);
% Create an instance of the helper plotting object DOADisplay. This will be
% display the estimated DOA live with an arrow in a polar plot.
DOAPointer = dspdemo.DOADisplay();

bufferLength = 64;

% Use a helper object to rearrange the input samples according the how the
% microphone pairs are selected
Preprocessor = dspdemo.PairArrayPreprocessor(...
    'MicPositions', micPositions,...
    'MicPairs', micPairs,...
    'BufferLength', bufferLength);
micSeparations = getPairSeparations(Preprocessor);

% The main algorithmic builing block of this example is a cross-correlator.
% That is used in conjunction with an interpolator to ensure a finer DOA
% resolution. In this simple case it is sufficient to use the same two
% objects across the different pairs available. In general, however,
% different channels may need to independently save their internal states
% and hence to be handled by separate objects.
XCorrelator = dsp.Crosscorrelator(...
    'Method', 'Frequency Domain');
interpFactor = 8;
b = interpFactor * fir1((2*interpFactor*8-1),1/interpFactor);
groupDelay = median(grpdelay(b));
Interpolator = dsp.FIRInterpolator(...
    'InterpolationFactor',interpFactor,...
    'Numerator',b);

tic
while(toc < endTime)
    cycleStart = toc;
    % Read a multichannel frame from the audio source
    % The returned array is of size AudioFrameLenght x size(micPositions,2)
    multichannelAudioFrame = step(AudioInput);

    % Rearrange the acquired sample in 4-D array of size
    % bufferLength x numBuffers x 2 x numPairs where 2 is the number of
    % channels per microphone pair
    bufferedFrame = step(Preprocessor, multichannelAudioFrame);

    % First estimate the DOA for each pair, independently

    % Initialize arrays uses across available pairs
    numBuffers = size(bufferedFrame, 2);
    delays = zeros(1,numPairs);
    anglesInRadians = zeros(1,numPairs);
    xcDense = zeros((2*bufferLength-1)*interpFactor, numPairs);

    % Loop through available pairs
    for kPair = 1:numPairs
        % Estimate inter-microphone delay for each 2-channel buffer
        delayVector = zeros(numBuffers, 1);
        for kBuffer = 1:numBuffers
            % Cross-correlate pair channels to get a coarse
            % crosscorrelation
            xcCoarse = step(XCorrelator, ...
                bufferedFrame(:,kBuffer,1,kPair), ...
                bufferedFrame(:,kBuffer,2,kPair));

            % Interpolate to increase spatial resolution
            xcDense = step(Interpolator, flipud(xcCoarse));

            % Extract position of maximum, equal to delay in sample time
            % units, including the group delay of the interpolation filter
            [~,idx] = max(xcDense);
            delayVector(kBuffer) = ...
                (idx - groupDelay)/interpFactor - bufferLength;
        end

        % Combine DOA estimation across pairs by selecting the median value
        delays(kPair) = median(delayVector);

        % Convert delay into angle using the microsoft pair spatial
        % separtions provided
        anglesInRadians(kPair) = HelperDelayToAngle(delays(kPair), fs, ...
            micSeparations(kPair));
    end

    % Combine DOA estimation across pairs by keeping only the median value
    DOAInRadians = median(anglesInRadians);

    % Arrow display
    step(DOAPointer, DOAInRadians)
end

release(AudioInput)

end

