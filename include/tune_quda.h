#ifndef _TUNE_QUDA_H
#define _TUNE_QUDA_H

#include <quda_internal.h>
#include <dirac_quda.h>

#include <string>
#include <iostream>
#include <iomanip>
#include <cstring>
#include <cfloat>
#include <stdarg.h>
#include <tune_key.h>

namespace quda {

  class TuneParam {

  public:
    dim3 block;
    dim3 grid;
    int shared_bytes;
    int4 aux; // free parameter that can be used as an arbitrary autotuning dimension outside of launch parameters

    std::string comment;
    float time;
    long long n_calls;

    inline TuneParam() : block(32, 1, 1), grid(1, 1, 1), shared_bytes(0), aux(), time(FLT_MAX), n_calls(0) {
      aux = make_int4(1,1,1,1);
    }

    inline TuneParam(const TuneParam &param)
      : block(param.block), grid(param.grid), shared_bytes(param.shared_bytes), aux(param.aux), comment(param.comment), time(param.time), n_calls(param.n_calls) { }

    inline TuneParam& operator=(const TuneParam &param) {
      if (&param != this) {
	block = param.block;
	grid = param.grid;
	shared_bytes = param.shared_bytes;
	aux = param.aux;
	comment = param.comment;
	time = param.time;
	n_calls = param.n_calls;
      }
      return *this;
    }

    friend std::ostream& operator<<(std::ostream& output, const TuneParam& param) {
      output << "block = (" << param.block.x << ", " << param.block.y << ", " << param.block.z << ")" << std::endl;
      output << "grid = (" << param.grid.x << ", " << param.grid.y << ", " << param.grid.z << ")" << std::endl;
      output << "shared_bytes = " << param.shared_bytes << std::endl;
      output << "aux = (" << param.aux.x << ", " << param.aux.y << ", " << param.aux.z << ", " << param.aux.w << ")" << std::endl;
      output << param.comment << std::endl;
      return output;
    }
  };


  class Tunable {

  protected:
    virtual long long flops() const = 0;
    virtual long long bytes() const { return 0; } // FIXME

    // the minimum number of shared bytes per thread
    virtual unsigned int sharedBytesPerThread() const = 0;

    // the minimum number of shared bytes per thread block
    virtual unsigned int sharedBytesPerBlock(const TuneParam &param) const = 0;

    // override this if a specific thread count is required (e.g., if not grid size tuning)
    virtual unsigned int minThreads() const { return 1; }
    virtual bool tuneGridDim() const { return true; }
    virtual bool tuneAuxDim() const { return false; }
    virtual bool tuneSharedBytes() const { return true; }

    virtual bool advanceGridDim(TuneParam &param) const
    {
      if (tuneGridDim()) {
	const unsigned int max_blocks = 2*deviceProp.multiProcessorCount;
	const int step = 1;
	param.grid.x += step;
	if (param.grid.x > max_blocks) {
	  param.grid.x = step;
	  return false;
	} else {
	  return true;
	}
      } else {
	return false;
      }
    }

    virtual unsigned int maxBlockSize() const { return deviceProp.maxThreadsDim[0]; }

    virtual int blockStep() const { return deviceProp.warpSize; }
    virtual int blockMin() const { return deviceProp.warpSize; }

    static unsigned int setBlockThreshold() {
      char *threshold_char = getenv("QUDA_TUNING_THRESHOLD");
      int threshold = deviceProp.maxThreadsDim[0];
      if (threshold_char) {
	threshold = atoi(threshold_char);
	if (threshold > deviceProp.maxThreadsDim[0])
	  errorQuda("Invalid QUDA_TUNING_THRESHOLD %d", threshold);
      }
      return threshold;
    }

    virtual bool advanceBlockDim(TuneParam &param) const
    {
      const static unsigned int block_threshold = setBlockThreshold();
      const unsigned int max_threads = maxBlockSize();
      const unsigned int max_blocks = deviceProp.maxGridSize[0];
      const unsigned int max_shared = deviceProp.sharedMemPerBlock;
      const int step = blockStep();
      bool ret;

      // increment by step if less than threshold else double
      param.block.x = param.block.x < block_threshold ? param.block.x+step : param.block.x*2;

      int nthreads = param.block.x*param.block.y*param.block.z;
      if (param.block.x > max_threads || sharedBytesPerThread()*nthreads > max_shared) {

	if (tuneGridDim()) {
	  param.block.x = step;
	} else { // not tuning the grid dimension so have to set a valid grid size
	  // ensure the blockDim is large enough given the limit on gridDim
	  param.block.x = (minThreads()+max_blocks-1)/max_blocks;
	  param.block.x = ((param.block.x+step-1)/step)*step; // round up to nearest step size
	  if(param.block.x > max_threads) errorQuda("Local lattice volume is too large for device");
	}

	ret = false;
      } else {
	ret = true;
      }

      if (!tuneGridDim()) 
	param.grid = dim3((minThreads()+param.block.x-1)/param.block.x, 1, 1);

      return ret;
    }

    /**
     * @brief For reason this can't be queried from the device properties, so
     * here we set set this.  Based on Table 14 of the CUDA
     * Programming Guide 9.0 (Technical Specifications per Compute Capability)
     * @return The maximum number of simultaneously resident blocks per SM
     */
    unsigned int maxBlocksPerSM() const {
      switch (deviceProp.major) {
      case 2:
	return 8;
      case 3:
	return 16;
      case 5:
      case 6:
      case 7:
	return 32;
      default:
	errorQuda("Unknown SM architecture %d.%d\n", deviceProp.major, deviceProp.minor);
	return 0;
      }
    }

    /**
     * The goal here is to throttle the number of thread blocks per SM by over-allocating shared memory (in order to improve
     * L2 utilization, etc.).  Note that:
     * - On Fermi/Kepler, requesting greater than 16 KB will switch the cache config, so we restrict ourselves to 16 KB for now.
     *   We thus request the smallest amount of dynamic shared memory that guarantees throttling to a given number of blocks,
     *   in order to allow some extra leeway.
     */
    virtual bool advanceSharedBytes(TuneParam &param) const
    {
      if (tuneSharedBytes()) {
	const int max_shared = deviceProp.sharedMemPerBlock;
	const int max_blocks_per_sm = std::min(deviceProp.maxThreadsPerMultiProcessor / (param.block.x*param.block.y*param.block.z), maxBlocksPerSM());
	int blocks_per_sm = max_shared / (param.shared_bytes ? param.shared_bytes : 1);
	if (blocks_per_sm > max_blocks_per_sm) blocks_per_sm = max_blocks_per_sm;
	param.shared_bytes = (blocks_per_sm > 0 ? max_shared / blocks_per_sm + 1 : max_shared + 1);

	if (param.shared_bytes > max_shared) {
	  TuneParam next(param);
	  advanceBlockDim(next); // to get next blockDim
	  int nthreads = next.block.x * next.block.y * next.block.z;
	  param.shared_bytes = sharedBytesPerThread()*nthreads > sharedBytesPerBlock(param) ?
	    sharedBytesPerThread()*nthreads : sharedBytesPerBlock(param);
	  return false;
	} else {
	  return true;
	}
      } else {
	return false;
      }
    }

    virtual bool advanceAux(TuneParam &param) const { return false; }

    char aux[TuneKey::aux_n];

    void writeAuxString(const char *format, ...) {
      va_list arguments;
      va_start(arguments, format);
      int n = vsnprintf(aux, TuneKey::aux_n, format, arguments);
      //int n = snprintf(aux, QUDA_TUNE_AUX_STR_LENGTH, "threads=%d,prec=%lu,stride=%d,geometery=%d",
      //	       arg.volumeCB,sizeof(Complex)/2,arg.forceOffset);
      if (n < 0 || n >=TuneKey::aux_n) errorQuda("Error writing auxiliary string");
    }

  public:
    Tunable() { }
    virtual ~Tunable() { }
    virtual TuneKey tuneKey() const = 0;
    virtual void apply(const cudaStream_t &stream) = 0;
    virtual void preTune() { }
    virtual void postTune() { }
    virtual int tuningIter() const { return 1; }

    virtual std::string paramString(const TuneParam &param) const
      {
	std::stringstream ps;
	ps << "block=(" << param.block.x << "," << param.block.y << "," << param.block.z << "), ";
	if (tuneGridDim()) ps << "grid=(" << param.grid.x << "," << param.grid.y << "," << param.grid.z << "), ";
	ps << "shared=" << param.shared_bytes << ", ";

	// determine if we are tuning the auxiliary dimension
	if (tuneAuxDim()) ps << "aux=(" << param.aux.x << "," << param.aux.y << "," << param.aux.z << "," << param.aux.w << ")";
	return ps.str();
      }

    virtual std::string perfString(float time) const
      {
	float gflops = flops() / (1e9 * time);
	float gbytes = bytes() / (1e9 * time);
	std::stringstream ss;
	ss << std::setiosflags(std::ios::fixed) << std::setprecision(2) << gflops << " Gflop/s, ";
	ss << gbytes << " GB/s";
	return ss.str();
      }

    virtual void initTuneParam(TuneParam &param) const
    {
      const unsigned int max_threads = deviceProp.maxThreadsDim[0];
      const unsigned int max_blocks = deviceProp.maxGridSize[0];
      const int min_block_size = blockMin();

      if (tuneGridDim()) {
	param.block = dim3(min_block_size,1,1);

	param.grid = dim3(1,1,1);
      } else {
	// find the minimum valid blockDim
	param.block = dim3((minThreads()+max_blocks-1)/max_blocks, 1, 1);
	param.block.x = ((param.block.x+min_block_size-1) / min_block_size) * min_block_size; // round up to the nearest multiple of desired minimum block size
	if (param.block.x > max_threads) errorQuda("Local lattice volume is too large for device");

	param.grid = dim3((minThreads()+param.block.x-1)/param.block.x, 1, 1);
      }
      param.shared_bytes = sharedBytesPerThread()*param.block.x > sharedBytesPerBlock(param) ?
	sharedBytesPerThread()*param.block.x : sharedBytesPerBlock(param);
    }

    /** sets default values for when tuning is disabled */
    virtual void defaultTuneParam(TuneParam &param) const
    {
      initTuneParam(param);
      if (tuneGridDim()) param.grid = dim3(128,1,1);
    }

    virtual bool advanceTuneParam(TuneParam &param) const
    {
      return advanceSharedBytes(param) || advanceBlockDim(param) || advanceGridDim(param) || advanceAux(param);
    }

    /**
     * Check the launch parameters of the kernel to ensure that they are
     * valid for the current device.
     */
    void checkLaunchParam(TuneParam &param) {
    
      if (param.block.x > (unsigned int)deviceProp.maxThreadsDim[0])
	errorQuda("Requested X-dimension block size %d greater than hardware limit %d", 
		  param.block.x, deviceProp.maxThreadsDim[0]);
      
      if (param.block.y > (unsigned int)deviceProp.maxThreadsDim[1])
	errorQuda("Requested Y-dimension block size %d greater than hardware limit %d", 
		  param.block.y, deviceProp.maxThreadsDim[1]);
	
      if (param.block.z > (unsigned int)deviceProp.maxThreadsDim[2])
	errorQuda("Requested Z-dimension block size %d greater than hardware limit %d", 
		  param.block.z, deviceProp.maxThreadsDim[2]);
	  
      if (param.grid.x > (unsigned int)deviceProp.maxGridSize[0]){
	errorQuda("Requested X-dimension grid size %d greater than hardware limit %d", 
		  param.grid.x, deviceProp.maxGridSize[0]);

      }
      if (param.grid.y > (unsigned int)deviceProp.maxGridSize[1])
	errorQuda("Requested Y-dimension grid size %d greater than hardware limit %d", 
		  param.grid.y, deviceProp.maxGridSize[1]);
    
      if (param.grid.z > (unsigned int)deviceProp.maxGridSize[2])
	errorQuda("Requested Z-dimension grid size %d greater than hardware limit %d", 
		  param.grid.z, deviceProp.maxGridSize[2]);
    }

  };

  
  /**
     This derived class is for algorithms that deploy parity across
     the y dimension of the thread block with no shared memory tuning.
     The x threads will typically correspond to the checkboarded
     volume.
   */
  class TunableLocalParity : public Tunable {

  protected:
    unsigned int sharedBytesPerThread() const { return 0; }
    unsigned int sharedBytesPerBlock(const TuneParam &param) const { return 0; }

    // don't tune the grid dimension
    bool tuneGridDim() const { return false; }

    /**
       The maximum block size in the x dimension is the total number
       of threads divided by the size of the y dimension
     */
    unsigned int maxBlockSize() const { return deviceProp.maxThreadsPerBlock / 2; }

  public:
    bool advanceBlockDim(TuneParam &param) const {
      bool rtn = Tunable::advanceBlockDim(param);
      param.block.y = 2;
      return rtn;
    }
    
    void initTuneParam(TuneParam &param) const {
      Tunable::initTuneParam(param);
      param.block.y = 2;
    }

    void defaultTuneParam(TuneParam &param) const {
      Tunable::defaultTuneParam(param);
      param.block.y = 2;
    }

  };
  
  /**
     This derived class is for algorithms that deploy a vector of
     computations across the y dimension of both the threads block and
     grid.  For example this could be parity in the y dimension and
     checkerboarded volume in x.
   */
  class TunableVectorY : public Tunable {

  protected:
    virtual unsigned int sharedBytesPerThread() const { return 0; }
    virtual unsigned int sharedBytesPerBlock(const TuneParam &param) const { return 0; }

    unsigned int vector_length_y;

  public:
    TunableVectorY(unsigned int vector_length_y) : vector_length_y(vector_length_y) { }

    bool advanceBlockDim(TuneParam &param) const
    {
      dim3 block = param.block;
      dim3 grid = param.grid;
      bool ret = Tunable::advanceBlockDim(param);
      param.block.y = block.y;
      param.grid.y = grid.y;

      if (ret) { // we advanced the block.x so we're done
	return true;
      } else { // block.x (spacetime) was reset

	// we can advance spin/block-color since this is valid
	if (param.block.y < vector_length_y && param.block.y < (unsigned int)deviceProp.maxThreadsDim[1]) {
	  param.block.y++;
	  param.grid.y = (vector_length_y + param.block.y - 1) / param.block.y;
	  return true;
	} else { // we have run off the end so let's reset
	  param.block.y = 1;
	  param.grid.y = vector_length_y;
	  return false;
	}
      }
    }

    void initTuneParam(TuneParam &param) const
    {
      Tunable::initTuneParam(param);
      param.block.y = 1;
      param.grid.y = vector_length_y;
    }

    /** sets default values for when tuning is disabled */
    void defaultTuneParam(TuneParam &param) const
    {
      Tunable::defaultTuneParam(param);
      param.block.y = 1;
      param.grid.y = vector_length_y;
    }

    void resizeVector(int y) { vector_length_y = y;  }
  };

  class TunableVectorYZ : public TunableVectorY {

    mutable unsigned vector_length_z;

  public:
    TunableVectorYZ(unsigned int vector_length_y, unsigned int vector_length_z)
      : TunableVectorY(vector_length_y), vector_length_z(vector_length_z) { }

    bool advanceBlockDim(TuneParam &param) const
    {
      dim3 block = param.block;
      dim3 grid = param.grid;
      bool ret = TunableVectorY::advanceBlockDim(param);
      param.block.z = block.z;
      param.grid.z = grid.z;

      if (ret) { // we advanced the block.y / block.x so we're done
	return true;
      } else { // block.x/block.y (spacetime) was reset

	// we can advance spin/block-color since this is valid
	if (param.block.z < vector_length_z && param.block.z < (unsigned int)deviceProp.maxThreadsDim[1]) {
	  param.block.z++;
	  param.grid.z = (vector_length_z + param.block.z - 1) / param.block.z;
	  return true;
	} else { // we have run off the end so let's reset
	  param.block.z = 1;
	  param.grid.z = vector_length_z;
	  return false;
	}
      }
    }

    void initTuneParam(TuneParam &param) const
    {
      TunableVectorY::initTuneParam(param);
      param.block.z = 1;
      param.grid.z = vector_length_z;
    }

    /** sets default values for when tuning is disabled */
    void defaultTuneParam(TuneParam &param) const
    {
      TunableVectorY::defaultTuneParam(param);
      param.block.z = 1;
      param.grid.z = vector_length_z;
    }

    void resizeVector(int y, int z) { vector_length_z = z;  TunableVectorY::resizeVector(y); }
  };

  void loadTuneCache();
  void saveTuneCache();

  /**
   * @brief Save profile to disk.
   */
  void saveProfile(const std::string label = "");

  /**
   * @brief Flush profile contents, setting all counts to zero.
   */
  void flushProfile();

  TuneParam& tuneLaunch(Tunable &tunable, QudaTune enabled, QudaVerbosity verbosity);

} // namespace quda

#endif // _TUNE_QUDA_H
