/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2022, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF THE BSD NEW LICENSE OR THE
 * GPL VERSION 3 LICENSE OR THE OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the OSMC (Open Source Modelica Consortium)
 * Public License (OSMC-PL) are obtained from OSMC, either from the above
 * address, from the URLs: http://www.openmodelica.org or
 * http://www.ida.liu.se/projects/OpenModelica, and in the OpenModelica
 * distribution. GNU version 3 is obtained from:
 * http://www.gnu.org/copyleft/gpl.html. The New BSD License is obtained from:
 * http://www.opensource.org/licenses/BSD-3-Clause.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE, EXCEPT AS
 * EXPRESSLY SET FORTH IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE
 * CONDITIONS OF OSMC-PL.
 *
 */

/*! \file gbode_sparse.h
 */

#ifndef _GBODE_SPARSE_H_
#define _GBODE_SPARSE_H_

#ifdef __cplusplus
extern "C" {
#endif

void ColoringAlg(SPARSE_PATTERN* sparsePattern, int sizeRows, int sizeCols, int nStages);

SPARSE_PATTERN* initializeSparsePattern_SR(DATA* data, NONLINEAR_SYSTEM_DATA* sysData);
SPARSE_PATTERN* initializeSparsePattern_IRK(DATA* data, NONLINEAR_SYSTEM_DATA* sysData);

void updateSparsePattern_MR(DATA_GBODE* gbData, SPARSE_PATTERN *sparsePattern_MR);

#ifdef __cplusplus
};
#endif

#endif  /* _GBODE_SPARSE_H_ */
