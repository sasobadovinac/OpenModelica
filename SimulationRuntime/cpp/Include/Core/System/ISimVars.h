#pragma once

/**
* Class for SimVars, stores all model variable in continuous block of memory
*/
class ISimVars
{
public:

   virtual ~ISimVars() {};

      /*Methods for access model variables*/
     virtual double* getStateVector()= 0;
     virtual double* getDerStateVector()= 0;
     virtual const double* getRealVarsVector() const= 0;
     virtual const int* getIntVarsVector() const= 0;
     virtual const bool* getBoolVarsVector() const= 0;
     virtual  void setRealVarsVector(const double* vars) = 0;
     virtual  void setIntVarsVector(const int* vars) = 0;
     virtual  void setBoolVarsVector(const bool* vars) = 0;


     /*Methods for initialize model array variables in simvars memory*/
    virtual double* initRealArrayVar(size_t size,size_t start_index)= 0;
    virtual int*    initIntArrayVar(size_t size,size_t start_index)= 0;
    virtual bool*   initBoolArrayVar(size_t size,size_t start_index)= 0;
    virtual void initRealAliasArray(int indices[], size_t n, const double* ref_data[]) = 0;
    virtual void initIntAliasArray(int indices[], size_t n, const int* ref_data[]) = 0;
    virtual void initBoolAliasArray(int indices[], size_t n, const bool* ref_data[]) = 0;
    virtual void initRealAliasArray(std::vector<int> indices, const double* ref_data[]) = 0;
    virtual void initIntAliasArray(std::vector<int> indices, const int* ref_data[]) = 0;
    virtual void initBoolAliasArray(std::vector<int> indices, const bool* ref_data[]) = 0;
    /*Methods for initialize scalar model variables in simvars memory*/
    virtual double& initRealVar(size_t i) = 0;
    virtual int& initIntVar(size_t i)= 0;
    virtual bool& initBoolVar(size_t i)= 0;

     /*Methods for pre- variables*/


     virtual void savePreVariables() = 0;
     virtual void initPreVariables()= 0;
     /*access methods for pre-variable*/
     virtual double& getPreVar(double& var)=0;
     virtual double& getPreVar(int& var)=0;
     virtual double& getPreVar(bool& var)=0;
     virtual void setPreVar(double& var)=0;
     virtual void setPreVar(int& var)=0;
     virtual void setPreVar(bool& var)=0;
};
