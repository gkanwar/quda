#ifndef _LATTICE_FIELD_H
#define _LATTICE_FIELD_H

#include <quda.h>
#include <iostream>

/**
 * @file lattice_field.h
 *
 * @section DESCRIPTION 
 *
 * LatticeField is an abstract base clase for all Field objects.
 */

namespace quda {

  // Forward declaration of all children
  class ColorSpinorField;
  class cudaColorSpinorField;
  class cpuColorSpinorField;

  class GaugeField;
  class cpuGaugeField;
  class cudaGaugeField;

  class CloverField;
  class cudaCloverField;
  class cpuCloverField;

  struct LatticeFieldParam {
    int nDim;
    int x[QUDA_MAX_DIM];
    int pad;

    QudaPrecision precision;
    QudaVerbosity verbosity;

    LatticeFieldParam() 
    : nDim(0), pad(0), precision(QUDA_INVALID_PRECISION), verbosity(QUDA_SILENT) { 
      for (int i=0; i<nDim; i++) x[i] = 0; 
    }

    LatticeFieldParam(int nDim, const int *x, int pad, QudaPrecision precision, 
		      QudaVerbosity verbosity) 
    : nDim(nDim), pad(pad), precision(precision), verbosity(verbosity) { 
      if (nDim > QUDA_MAX_DIM) errorQuda("Number of dimensions too great");
      for (int i=0; i<nDim; i++) this->x[i] = x[i]; 
    }
    
    /**
       Constructor for creating a LatticeField from a QudaGaugeParam
       @param param Contains the metadate for creating the
       LatticeField
    */
    LatticeFieldParam(const QudaGaugeParam &param) 
    : nDim(4), pad(0), precision(param.cpu_prec), verbosity(QUDA_SILENT)  {
      for (int i=0; i<nDim; i++) this->x[i] = param.X[i];
    }
  };

  std::ostream& operator<<(std::ostream& output, const LatticeFieldParam& param);

  class LatticeField {

  protected:
    int volume; // lattice volume
    int volumeCB; // the checkboarded volume
    int stride;
    int pad;
  
    size_t total_bytes;

    int nDim;
    int x[QUDA_MAX_DIM];

    int surface[QUDA_MAX_DIM];
    int surfaceCB[QUDA_MAX_DIM];

    /**
       The precision of the field 
    */
    QudaPrecision precision;

    /**
       The verbosity to use for this field
    */
    QudaVerbosity verbosity;

    /**
	Pinned-memory buffer that is used by all derived classes 
    */
    static void *bufferPinned; 

    /** Whether the pinned-memory buffer has already been initialized or not */
    static bool bufferPinnedInit;

    /** The size in bytes of pinned-memory buffer */
    static size_t bufferPinnedBytes;

    /** Resize the pinned-memory buffer */
    void resizeBufferPinned(size_t bytes) const;

    /** Device-memory buffer that is used by all derived classes */
    static void *bufferDevice; 

    /** Whether the device-memory buffer has already been initialized or not */
    static bool bufferDeviceInit;

    /** The size in bytes of device-memory buffer */
    static size_t bufferDeviceBytes;

    /** Resize the device-memory buffer */
    void resizeBufferDevice(size_t bytes) const;

 public:

    /**
       Constructor for creating a LatticeField from a LatticeFieldParam
       @param param Contains the metadata for creating the LatticeField
    */
    LatticeField(const LatticeFieldParam &param);

    /**
       Destructor for LatticeField
    */
    virtual ~LatticeField() { ; }
    
    /**
       Free the pinned-memory buffer 
    */
    static void freeBuffer();
    
    /**
       @return The dimension of the lattice 
    */
    int Ndim() const { return nDim; }
    
    /**
       @return The pointer to the lattice-dimension array
    */
    const int* X() const { return x; }
    
    /**
       @return The full-field volume
    */
    int Volume() const { return volume; }
    
    /**
       @return The single-parity volume
    */
    int VolumeCB() const { return volumeCB; }
    
    /**
       @param i The dimension of the requested surface 
       @return The single-parity surface of dimension i
    */
    const int* SurfaceCB() const { return surfaceCB; }
    
    /**
       @param i The dimension of the requested surface 
       @return The single-parity surface of dimension i
    */
    int SurfaceCB(const int i) const { return surfaceCB[i]; }
    
    /**
       @return The single-parity stride of the field     
    */
    int Stride() const { return stride; }
    
    /**
       @return The field padding
    */
    int Pad() const { return pad; }
    
    /**
       @return The field precision
    */
    QudaPrecision Precision() const { return precision; }
    
    /**
       @return The location of the field
    */
    QudaFieldLocation Location() const;
    
    /**
       @return The verbosity of the field
    */
    QudaVerbosity Verbosity() const { return verbosity; }
    
    /**
       @return The total storage allocated
    */
    size_t GBytes() const { return total_bytes / (1<<30); }
    
    /**
       Check that the metadata of *this and a are compatible
       @param a The LatticeField to which we are comparing
    */
    void checkField(const LatticeField &a);
    
    /**
       Read in the field specified by filenemae
       @param filename The name of the file to read
    */
    virtual void read(char *filename);
    
    /**
       Write the field in the file specified by filename
       @param filename The name of the file to write
    */
    virtual void write(char *filename);
    
  };
  
} // namespace quda

#endif // _LATTICE_FIELD_H